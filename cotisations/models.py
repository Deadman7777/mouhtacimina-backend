from django.db import models
from django.db.models import Sum
from django.utils import timezone
from decimal import Decimal
from accounts.models import User, Cellule


class Cotisation(models.Model):

    class TypeCotisation(models.TextChoices):
        MENSUELLE   = 'mensuelle',   'Cotisation Mensuelle (1000 FCFA)'
        EVENEMENT   = 'evenement',   'Cotisation Événement'
        EXCEPTIONNELLE = 'exceptionnelle', 'Cotisation Exceptionnelle'

    class Periodicite(models.TextChoices):
        MENSUELLE = 'mensuelle', 'Mensuelle'
        ANNUELLE  = 'annuelle',  'Annuelle'
        UNIQUE    = 'unique',    'Unique'

    titre            = models.CharField(max_length=200)
    description      = models.TextField(blank=True)
    type_cotisation  = models.CharField(
        max_length=15,
        choices=TypeCotisation.choices,
        default=TypeCotisation.EVENEMENT
    )

    # null = campagne globale, sinon par cellule
    cellule          = models.ForeignKey(
        Cellule, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='cotisations'
    )

    montant_suggere  = models.DecimalField(
        max_digits=10, decimal_places=2,
        null=True, blank=True,
        help_text="Laisser vide si montant libre"
    )

    # Réduction pour membres officiels sur cotisations événement
    reduction_membres_officiels = models.DecimalField(
        max_digits=10, decimal_places=2,
        default=Decimal('0'),
        help_text="Réduction accordée aux membres officiels (en FCFA)"
    )

    periodicite   = models.CharField(
        max_length=15, choices=Periodicite.choices,
        default=Periodicite.UNIQUE
    )
    date_limite   = models.DateField(null=True, blank=True)
    est_active    = models.BooleanField(default=True)

    # Mois concerné (pour cotisations mensuelles)
    mois_concerne = models.DateField(
        null=True, blank=True,
        help_text="Pour les cotisations mensuelles : le mois concerné (ex: 2024-01-01 = Janvier 2024)"
    )

    cree_par      = models.ForeignKey(
        User, on_delete=models.SET_NULL,
        null=True, related_name='cotisations_creees'
    )
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Cotisation'
        ordering = ['-date_creation']
        verbose_name_plural = 'Cotisations'

    def __str__(self):
        return f"{self.titre} ({self.get_type_cotisation_display()})"

    def montant_pour_membre(self, membre):
        """
        Retourne le montant à payer pour un membre donné,
        en appliquant la réduction si membre officiel.
        """
        if self.montant_suggere is None:
            return None
        if membre.est_officiel and self.reduction_membres_officiels > 0:
            return max(
                self.montant_suggere - self.reduction_membres_officiels,
                Decimal('0')
            )
        return self.montant_suggere

    @property
    def total_collecte(self):
        return self.paiements.filter(
            statut='valide'
        ).aggregate(t=Sum('montant'))['t'] or Decimal('0')

    @property
    def nb_paiements_valides(self):
        return self.paiements.filter(statut='valide').count()

    @property
    def nb_en_attente(self):
        return self.paiements.filter(statut='en_attente').count()


class Paiement(models.Model):

    class Moyen(models.TextChoices):
        WAVE         = 'wave',         'Wave'
        ORANGE_MONEY = 'orange_money', 'Orange Money'
        FREE_MONEY   = 'free_money',   'Free Money'
        ESPECES      = 'especes',      'Espèces'

    class Statut(models.TextChoices):
        EN_ATTENTE = 'en_attente', 'En attente'
        VALIDE     = 'valide',     'Validé'
        REJETE     = 'rejete',     'Rejeté'

    cotisation  = models.ForeignKey(
        Cotisation, on_delete=models.CASCADE, related_name='paiements'
    )
    membre      = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='paiements'
    )
    montant     = models.DecimalField(max_digits=10, decimal_places=2)
    moyen       = models.CharField(max_length=20, choices=Moyen.choices)
    statut      = models.CharField(
        max_length=15, choices=Statut.choices, default=Statut.EN_ATTENTE
    )

    # Référence transaction mobile money
    reference_transaction = models.CharField(
        max_length=100, blank=True,
        help_text="Numéro de transaction Wave/OM saisi par le membre"
    )

    # Capture du montant après réduction appliquée
    reduction_appliquee = models.DecimalField(
        max_digits=10, decimal_places=2,
        default=Decimal('0'),
        help_text="Réduction appliquée au moment du paiement"
    )

    date_paiement    = models.DateTimeField(auto_now_add=True)
    date_validation  = models.DateTimeField(null=True, blank=True)
    valide_par       = models.ForeignKey(
        User, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='paiements_valides'
    )
    note = models.TextField(blank=True)

    class Meta:
        verbose_name = 'Paiement'
        ordering = ['-date_paiement']
        verbose_name_plural = 'Paiements'
        ordering = ['-date_paiement']

    def __str__(self):
        return f"{self.membre} — {self.montant} FCFA ({self.get_statut_display()})"

    def save(self, *args, **kwargs):
        # Capturer la réduction au moment de la création
        if not self.pk and self.reduction_appliquee == 0:
            self.reduction_appliquee = self.cotisation.reduction_membres_officiels \
                if self.membre.est_officiel else Decimal('0')
        super().save(*args, **kwargs)


class CotisationMensuelleConfig(models.Model):
    """
    Configuration globale de la cotisation mensuelle.
    Une seule instance (singleton).
    """
    montant_mensuel = models.DecimalField(
        max_digits=10, decimal_places=2,
        default=Decimal('1000'),
        help_text="Montant mensuel obligatoire pour les membres officiels"
    )
    jour_rappel     = models.IntegerField(
        default=1,
        help_text="Jour du mois pour envoyer la notification de rappel (1-28)"
    )
    date_modification = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Config Cotisation Mensuelle'

    def __str__(self):
        return f"Cotisation mensuelle : {self.montant_mensuel} FCFA"

    @classmethod
    def get(cls):
        """Récupère ou crée la config singleton."""
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj
