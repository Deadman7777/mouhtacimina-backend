from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class Cellule(models.Model):
    class Nom(models.TextChoices):
        UGB      = 'UGB',      'Cellule UGB (Mère)'
        DAKAR    = 'DAKAR',    'Cellule Dakar'
        NORD     = 'NORD',     'Cellule Nord'
        DIASPORA = 'DIASPORA', 'Cellule Diaspora'

    # Type de barème de cotisation appliqué aux membres de la cellule
    class TypeBareme(models.TextChoices):
        MENSUEL = 'mensuel', 'Mensuel (étudiants)'   # 1000 FCFA / mois
        ANNUEL  = 'annuel',  'Annuel (anciens)'      # 50000 FCFA / an
        AUCUN   = 'aucun',   'Aucun (en attente)'    # Diaspora pour l'instant

    nom           = models.CharField(max_length=20, choices=Nom.choices, unique=True)
    description   = models.TextField(blank=True)
    date_creation = models.DateField(auto_now_add=True)

    # ── Barème de cotisation de la cellule ───────────────────
    type_bareme = models.CharField(
        max_length=10,
        choices=TypeBareme.choices,
        default=TypeBareme.MENSUEL,
        help_text="Mensuel = 1000/mois (UGB), Annuel = 50000/an (Dakar, Nord)"
    )
    montant_cotisation = models.DecimalField(
        max_digits=10, decimal_places=2,
        default=1000,
        help_text="Montant de référence : 1000 (mensuel) ou 50000 (annuel)"
    )

    class Meta:
        verbose_name = 'Cellule'
        ordering = ['nom']

    def __str__(self):
        return self.get_nom_display()

    @property
    def est_annuel(self):
        return self.type_bareme == self.TypeBareme.ANNUEL

    @property
    def est_mensuel(self):
        return self.type_bareme == self.TypeBareme.MENSUEL


class User(AbstractUser):

    # ── Rôle applicatif ──────────────────────────────────────
    class Role(models.TextChoices):
        SUPER_ADMIN   = 'super_admin',   'Super Admin'
        ADMIN_CELLULE = 'admin_cellule', 'Admin Cellule'
        MEMBRE        = 'membre',        'Membre'

    # ── Type de membre ───────────────────────────────────────
    class TypeMembre(models.TextChoices):
        OFFICIEL    = 'officiel',    'Membre Officiel'
        SYMPATHISANT = 'sympathisant', 'Sympathisant'

    # ── Postes du bureau ─────────────────────────────────────
    class PosteBureau(models.TextChoices):
        PRESIDENT         = 'president',          'Président'
        VICE_PRESIDENT    = 'vice_president',      'Vice-Président'
        SG                = 'sg',                 'Secrétaire Général'
        PDTE_FINANCE      = 'pdte_finance',        'Pdte Commission Finance'
        TRESORIER         = 'tresorier',           'Trésorier Général'
        ADJT_TRESORIER    = 'adjt_tresorier',      'Adjoint Trésorier'
        COM_ORGANISATION  = 'com_organisation',    'Commission Organisation'
        COM_LOGISTIQUE    = 'com_logistique',      'Commission Logistique'
        COM_SCIENTIFIQUE  = 'com_scientifique',    'Commission Scientifique et Culturelle'
        CELLULE_COMM      = 'cellule_comm',        'Cellule Communication'
        COM_SAGES         = 'com_sages',           'Commission des Sages'

    # ── UFR ──────────────────────────────────────────────────
    class Ufr(models.TextChoices):
        SAT    = 'SAT',   'Sciences Appliquées et Technologies'
        SEG    = 'SEG',   'Sciences Économiques et Gestion'
        IPSL   = 'IPSL',  'IPSL'
        SANTE  = '2S',    'Santé'
        AGRO   = '2SATA', 'Agronomie'
        DROIT  = 'SJP',   'Droit'
        LANGUE = 'LSH',   'Langues et Sciences Humaines'
        TEACH  = 'SEFS',  "Sciences de l'Éducation"
        SPORT  = 'STAPS', 'STAPS'

    class StatutMatrimonial(models.TextChoices):
        MARIE       = 'marie',       'Marié(e)'
        CELIBATAIRE = 'celibataire', 'Célibataire'

    # ── Infos de base ────────────────────────────────────────
    email              = models.EmailField(unique=True)
    telephone          = models.CharField(max_length=20, blank=True)
    photo              = models.ImageField(upload_to='photos/', null=True, blank=True)
    date_naissance     = models.DateField(null=True, blank=True)
    adresse            = models.CharField(max_length=200, blank=True)
    statut_matrimonial = models.CharField(
        max_length=15, choices=StatutMatrimonial.choices, blank=True
    )

    # ── Rôle & cellule ───────────────────────────────────────
    role    = models.CharField(
        max_length=20, choices=Role.choices, default=Role.MEMBRE
    )
    cellule = models.ForeignKey(
        Cellule, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='membres'
    )
    date_adhesion = models.DateField(auto_now_add=True)
    est_actif     = models.BooleanField(default=True)

    # ── Type de membre ───────────────────────────────────────
    type_membre     = models.CharField(
        max_length=15,
        choices=TypeMembre.choices,
        default=TypeMembre.SYMPATHISANT,
        help_text="Officiel = carte membre + cotisation 1000 FCFA/mois obligatoire"
    )
    date_officialisation = models.DateField(
        null=True, blank=True,
        help_text="Date à laquelle le sympathisant est devenu membre officiel"
    )
    date_signature_engagement = models.DateField(
        null=True, blank=True,
        help_text="Date de signature de l'engagement de cotisation mensuelle"
    )

    # ── Bureau ───────────────────────────────────────────────
    est_bureau   = models.BooleanField(
        default=False,
        help_text="Est-il membre du bureau ?"
    )
    poste_bureau = models.CharField(
        max_length=25,
        choices=PosteBureau.choices,
        blank=True,
        help_text="Poste occupé au bureau (si est_bureau=True)"
    )

    # ── Infos académiques ────────────────────────────────────
    ufr           = models.CharField(max_length=10, choices=Ufr.choices, blank=True)
    specialite    = models.CharField(max_length=100, blank=True)
    niveau_etude  = models.CharField(max_length=20, blank=True)
    promo         = models.CharField(max_length=10, blank=True, help_text="Format P + numéro (ex: P30)")
    est_diplome   = models.BooleanField(default=False)
    annee_diplome = models.CharField(max_length=4, blank=True)

    USERNAME_FIELD  = 'email'
    REQUIRED_FIELDS = ['username', 'first_name', 'last_name']

    class Meta:
        verbose_name = 'Membre'
        verbose_name_plural = 'Membres'

    def __str__(self):
        return f"{self.get_full_name()} ({self.get_type_membre_display()})"

    @property
    def nom_complet(self):
        return self.get_full_name()

    @property
    def is_admin(self):
        return self.role in [self.Role.SUPER_ADMIN, self.Role.ADMIN_CELLULE]

    @property
    def est_officiel(self):
        return self.type_membre == self.TypeMembre.OFFICIEL

    @property
    def total_paye_mensuel(self):
        """
        Total des paiements validés sur cotisations mensuelles,
        effectués DEPUIS la date d'engagement actuelle.
        Ainsi, après une migration de cellule (qui réinitialise
        la date d'engagement), les anciens paiements ne comptent plus :
        le membre repart de zéro avec le nouveau barème.
        """
        from cotisations.models import Paiement
        from decimal import Decimal

        qs = Paiement.objects.filter(
            membre=self,
            statut='valide',
            cotisation__type_cotisation='mensuelle'
        )
        # Ne compter que les paiements postérieurs à l'engagement
        if self.date_signature_engagement:
            qs = qs.filter(
                date_paiement__date__gte=self.date_signature_engagement
            )

        return qs.aggregate(t=models.Sum('montant'))['t'] or Decimal('0')

    @property
    def dette_cotisation(self):
        """
        Calcule la dette accumulée du membre officiel.
        Le barème dépend de la cellule :
          - Cellule mensuelle (UGB)  : 1000 FCFA × mois depuis signature
          - Cellule annuelle (Dakar, Nord) : 50000 FCFA × années depuis signature
          - Cellule sans barème (Diaspora) : 0
        """
        from dateutil.relativedelta import relativedelta
        from decimal import Decimal

        # Pas officiel, pas de signature, ou pas de cellule => pas de dette
        if not self.est_officiel or not self.date_signature_engagement:
            return Decimal('0')
        if not self.cellule:
            return Decimal('0')

        aujourd_hui = timezone.now().date()
        debut       = self.date_signature_engagement
        diff        = relativedelta(aujourd_hui, debut)

        bareme = self.cellule.type_bareme

        if bareme == Cellule.TypeBareme.ANNUEL:
            # Anciens : 50000 par année entamée depuis la signature
            montant_annuel = self.cellule.montant_cotisation  # 50000
            nb_annees      = diff.years + 1  # +1 pour l'année en cours
            total_du       = montant_annuel * nb_annees

        elif bareme == Cellule.TypeBareme.MENSUEL:
            # Étudiants : 1000 par mois entamé depuis la signature
            montant_mensuel = self.cellule.montant_cotisation  # 1000
            nb_mois         = diff.years * 12 + diff.months + 1  # +1 mois en cours
            total_du        = montant_mensuel * nb_mois

        else:
            # Aucun barème (Diaspora en attente)
            return Decimal('0')

        dette = total_du - self.total_paye_mensuel
        return max(dette, Decimal('0'))

    @property
    def objectif_cotisation_label(self):
        """Texte décrivant l'objectif de cotisation selon la cellule."""
        if not self.cellule:
            return ''
        bareme = self.cellule.type_bareme
        montant = self.cellule.montant_cotisation
        if bareme == Cellule.TypeBareme.ANNUEL:
            return f'{montant:.0f} FCFA / an'
        if bareme == Cellule.TypeBareme.MENSUEL:
            return f'{montant:.0f} FCFA / mois'
        return ''

    def migrer_cellule(self, nouvelle_cellule, admin=None):
        """
        Migre le membre vers une nouvelle cellule.
        Les dettes en cours sont effacées (les anciens paiements mensuels
        non validés sont annulés et l'engagement est réinitialisé à aujourd'hui),
        et le nouvel objectif de cotisation s'applique immédiatement.
        """
        from cotisations.models import Paiement

        ancienne = self.cellule

        # 1. Annuler les paiements mensuels en attente (dette en cours)
        Paiement.objects.filter(
            membre=self,
            statut='en_attente',
            cotisation__type_cotisation='mensuelle'
        ).update(
            statut='rejete',
            note='Annulé suite à migration de cellule'
        )

        # 2. Réinitialiser l'engagement à aujourd'hui
        #    => repart de zéro avec le nouveau barème, dette = 0
        self.cellule                   = nouvelle_cellule
        self.date_signature_engagement = timezone.now().date()
        self.save(update_fields=['cellule', 'date_signature_engagement'])

        return {
            'ancienne_cellule': ancienne.get_nom_display() if ancienne else None,
            'nouvelle_cellule': nouvelle_cellule.get_nom_display(),
            'nouvel_objectif':  self.objectif_cotisation_label,
        }
