from django.db import models
from django.db.models import Sum
from accounts.models import User, Cellule


class Evenement(models.Model):
    class Type(models.TextChoices):
        GAMOU     = 'gamou',     'Gamou'
        ZIAR      = 'ziar',      'Ziar'
        REUNION   = 'reunion',   'Réunion'
        FORMATION = 'formation', 'Formation'
        AUTRE     = 'autre',     'Autre'

    class Statut(models.TextChoices):
        BROUILLON = 'brouillon', 'Brouillon'
        LANCE     = 'lance',     'Lancé'
        CLOTURE   = 'cloture',   'Clôturé'

    titre       = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    type        = models.CharField(max_length=20, choices=Type.choices)
    statut      = models.CharField(max_length=20, choices=Statut.choices, default=Statut.BROUILLON)

    # null = global (tout le dahira)
    cellule     = models.ForeignKey(
        Cellule, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='evenements'
    )
    est_global  = models.BooleanField(
        default=False,
        help_text="Si True, concerne toutes les cellules (ex: Gamou)"
    )

    lieu        = models.CharField(max_length=200, blank=True)
    date_debut  = models.DateTimeField()
    date_fin    = models.DateTimeField(null=True, blank=True)
    budget_prevu = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    cree_par    = models.ForeignKey(
        User, on_delete=models.SET_NULL,
        null=True, related_name='evenements_crees'
    )
    date_creation     = models.DateTimeField(auto_now_add=True)
    date_modification = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Événement'
        verbose_name_plural = 'Événements'
        ordering = ['-date_debut']

    def __str__(self):
        scope = "Global" if self.est_global else str(self.cellule)
        return f"{self.titre} ({scope})"

    @property
    def budget_reel(self):
        recettes = self.lignes_budget.filter(type='recette').aggregate(t=Sum('montant'))['t'] or 0
        depenses = self.lignes_budget.filter(type='depense').aggregate(t=Sum('montant'))['t'] or 0
        return recettes - depenses

    @property
    def nb_participants(self):
        return self.participations.filter(statut='present').count()


class Participation(models.Model):
    class Statut(models.TextChoices):
        INSCRIT = 'inscrit', 'Inscrit'
        PRESENT = 'present', 'Présent'
        ABSENT  = 'absent',  'Absent'

    membre    = models.ForeignKey(User, on_delete=models.CASCADE, related_name='participations')
    evenement = models.ForeignKey(Evenement, on_delete=models.CASCADE, related_name='participations')
    statut    = models.CharField(max_length=15, choices=Statut.choices, default=Statut.INSCRIT)
    date_inscription = models.DateTimeField(auto_now_add=True)
    note      = models.TextField(blank=True)

    class Meta:
        unique_together = ['membre', 'evenement']
        verbose_name = 'Participation'

    def __str__(self):
        return f"{self.membre} → {self.evenement}"


class LigneBudget(models.Model):
    class Type(models.TextChoices):
        RECETTE = 'recette', 'Recette'
        DEPENSE = 'depense', 'Dépense'

    evenement      = models.ForeignKey(Evenement, on_delete=models.CASCADE, related_name='lignes_budget')
    libelle        = models.CharField(max_length=200)
    type           = models.CharField(max_length=10, choices=Type.choices)
    montant        = models.DecimalField(max_digits=12, decimal_places=2)
    date           = models.DateField()
    note           = models.TextField(blank=True)
    enregistre_par = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)

    class Meta:
        verbose_name = 'Ligne budget'
        verbose_name_plural = 'Lignes budget'

    def __str__(self):
        return f"{self.libelle} — {self.montant} FCFA ({self.type})"
