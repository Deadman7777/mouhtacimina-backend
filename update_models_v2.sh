#!/bin/bash

# ============================================================
#   MOUHTACIMINA — Mise à jour modèles v2
#   Nouvelles précisions métier :
#   - Type membre (officiel / sympathisant)
#   - Bureau avec postes
#   - Dette cotisation mensuelle
#   - Réduction membres officiels sur events
# ============================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31d'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   MOUHTACIMINA — Modèles v2                         ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

# Activer le virtualenv
if [ -z "$VIRTUAL_ENV" ]; then
    for venv in env venv .venv; do
        [ -d "$venv" ] && source "$venv/bin/activate" && break
    done
fi

[ -f "manage.py" ] || error "Lance depuis la racine du projet Django"

# ─── 1. ACCOUNTS/MODELS.PY ───────────────────────────────────
log "Mise à jour accounts/models.py..."

cat > accounts/models.py << 'PYTHON'
from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class Cellule(models.Model):
    class Nom(models.TextChoices):
        UGB      = 'UGB',      'Cellule UGB (Mère)'
        DAKAR    = 'DAKAR',    'Cellule Dakar'
        NORD     = 'NORD',     'Cellule Nord'
        DIASPORA = 'DIASPORA', 'Cellule Diaspora'

    nom           = models.CharField(max_length=20, choices=Nom.choices, unique=True)
    description   = models.TextField(blank=True)
    date_creation = models.DateField(auto_now_add=True)

    class Meta:
        verbose_name = 'Cellule'

    def __str__(self):
        return self.get_nom_display()


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
    promo         = models.CharField(max_length=10, blank=True)
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
    def dette_cotisation(self):
        """
        Calcule la dette accumulée du membre officiel.
        Dette = (mois non payés depuis signature) × 1000 FCFA
        """
        if not self.est_officiel or not self.date_signature_engagement:
            return 0

        from cotisations.models import Paiement
        from dateutil.relativedelta import relativedelta
        from decimal import Decimal

        MONTANT_MENSUEL = Decimal('1000')
        aujourd_hui     = timezone.now().date()
        debut           = self.date_signature_engagement

        # Nombre de mois depuis la signature
        diff        = relativedelta(aujourd_hui, debut)
        total_mois  = diff.years * 12 + diff.months + 1  # +1 pour le mois en cours

        # Total dû
        total_du = MONTANT_MENSUEL * total_mois

        # Total payé sur cotisations mensuelles validées
        total_paye = Paiement.objects.filter(
            membre=self,
            statut='valide',
            cotisation__type_cotisation='mensuelle'
        ).aggregate(
            t=models.Sum('montant')
        )['t'] or Decimal('0')

        dette = total_du - total_paye
        return max(dette, Decimal('0'))  # jamais négatif
PYTHON
ok "accounts/models.py mis à jour"

# ─── 2. COTISATIONS/MODELS.PY ────────────────────────────────
log "Mise à jour cotisations/models.py..."

cat > cotisations/models.py << 'PYTHON'
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
PYTHON
ok "cotisations/models.py mis à jour"

# ─── 3. ADMIN MIS À JOUR ─────────────────────────────────────
log "Mise à jour accounts/admin.py..."

cat > accounts/admin.py << 'PYTHON'
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, Cellule


@admin.register(Cellule)
class CelluleAdmin(admin.ModelAdmin):
    list_display = ['nom', 'date_creation']


@admin.register(User)
class MembreAdmin(UserAdmin):
    list_display  = [
        'email', 'nom_complet', 'type_membre', 'role',
        'cellule', 'est_bureau', 'poste_bureau',
        'est_actif', 'est_diplome'
    ]
    list_filter   = [
        'type_membre', 'role', 'cellule',
        'est_bureau', 'est_actif', 'est_diplome', 'ufr'
    ]
    search_fields = ['email', 'first_name', 'last_name', 'username']
    ordering      = ['last_name', 'first_name']

    fieldsets = UserAdmin.fieldsets + (
        ('Dahira — Rôle & Cellule', {
            'fields': (
                'role', 'type_membre', 'cellule',
                'telephone', 'photo', 'date_naissance',
                'adresse', 'statut_matrimonial', 'est_actif',
                'date_officialisation', 'date_signature_engagement',
            )
        }),
        ('Bureau', {
            'fields': ('est_bureau', 'poste_bureau'),
            'classes': ('collapse',),
        }),
        ('Académique', {
            'fields': (
                'ufr', 'specialite', 'niveau_etude',
                'promo', 'est_diplome', 'annee_diplome'
            ),
            'classes': ('collapse',),
        }),
    )
PYTHON

cat > cotisations/admin.py << 'PYTHON'
from django.contrib import admin
from .models import Cotisation, Paiement, CotisationMensuelleConfig


class PaiementInline(admin.TabularInline):
    model          = Paiement
    extra          = 0
    readonly_fields = ['date_paiement', 'reduction_appliquee']
    fields         = [
        'membre', 'montant', 'moyen', 'statut',
        'reference_transaction', 'reduction_appliquee',
        'date_paiement', 'valide_par'
    ]


@admin.register(CotisationMensuelleConfig)
class ConfigAdmin(admin.ModelAdmin):
    list_display = ['montant_mensuel', 'jour_rappel', 'date_modification']


@admin.register(Cotisation)
class CotisationAdmin(admin.ModelAdmin):
    list_display  = [
        'titre', 'type_cotisation', 'cellule',
        'montant_suggere', 'reduction_membres_officiels',
        'est_active', 'total_collecte', 'nb_en_attente'
    ]
    list_filter   = ['type_cotisation', 'est_active', 'cellule']
    inlines       = [PaiementInline]


@admin.register(Paiement)
class PaiementAdmin(admin.ModelAdmin):
    list_display  = [
        'membre', 'cotisation', 'montant',
        'reduction_appliquee', 'moyen', 'statut', 'date_paiement'
    ]
    list_filter   = ['statut', 'moyen', 'cotisation__type_cotisation']
    search_fields = ['membre__email', 'reference_transaction']
    readonly_fields = ['date_paiement', 'reduction_appliquee']

    actions = ['valider_paiements', 'rejeter_paiements']

    def valider_paiements(self, request, queryset):
        from django.utils import timezone
        queryset.filter(statut='en_attente').update(
            statut='valide',
            valide_par=request.user,
            date_validation=timezone.now()
        )
    valider_paiements.short_description = "✓ Valider les paiements sélectionnés"

    def rejeter_paiements(self, request, queryset):
        queryset.filter(statut='en_attente').update(statut='rejete')
    rejeter_paiements.short_description = "✗ Rejeter les paiements sélectionnés"
PYTHON
ok "Admins mis à jour"

# ─── 4. SERIALIZERS MIS À JOUR ───────────────────────────────
log "Mise à jour accounts/serializers.py..."

cat > accounts/serializers.py << 'PYTHON'
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import User, Cellule


class CelluleSerializer(serializers.ModelSerializer):
    nom_display = serializers.CharField(source='get_nom_display', read_only=True)
    nb_membres  = serializers.SerializerMethodField()

    class Meta:
        model  = Cellule
        fields = ['id', 'nom', 'nom_display', 'description', 'date_creation', 'nb_membres']

    def get_nb_membres(self, obj):
        return obj.membres.filter(est_actif=True).count()


class MembreListSerializer(serializers.ModelSerializer):
    cellule_nom          = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    role_display         = serializers.CharField(source='get_role_display', read_only=True)
    type_membre_display  = serializers.CharField(source='get_type_membre_display', read_only=True)
    poste_bureau_display = serializers.CharField(source='get_poste_bureau_display', read_only=True)

    class Meta:
        model  = User
        fields = [
            'id', 'first_name', 'last_name', 'email',
            'telephone', 'photo',
            'role', 'role_display',
            'type_membre', 'type_membre_display',
            'cellule', 'cellule_nom',
            'est_bureau', 'poste_bureau', 'poste_bureau_display',
            'est_actif', 'est_diplome', 'date_adhesion',
        ]


class MembreDetailSerializer(serializers.ModelSerializer):
    cellule_nom          = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    role_display         = serializers.CharField(source='get_role_display', read_only=True)
    type_membre_display  = serializers.CharField(source='get_type_membre_display', read_only=True)
    ufr_display          = serializers.CharField(source='get_ufr_display', read_only=True)
    poste_bureau_display = serializers.CharField(source='get_poste_bureau_display', read_only=True)
    nom_complet          = serializers.CharField(read_only=True)
    dette_cotisation     = serializers.DecimalField(
        max_digits=10, decimal_places=2, read_only=True
    )

    class Meta:
        model  = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 'nom_complet',
            'email', 'telephone', 'photo', 'date_naissance', 'adresse',
            'statut_matrimonial',
            # Rôle & cellule
            'role', 'role_display', 'cellule', 'cellule_nom',
            'date_adhesion', 'est_actif',
            # Type membre
            'type_membre', 'type_membre_display',
            'date_officialisation', 'date_signature_engagement',
            'dette_cotisation',
            # Bureau
            'est_bureau', 'poste_bureau', 'poste_bureau_display',
            # Académique
            'ufr', 'ufr_display', 'specialite', 'niveau_etude',
            'promo', 'est_diplome', 'annee_diplome',
        ]
        read_only_fields = ['date_adhesion', 'email', 'dette_cotisation']


class InscriptionSerializer(serializers.ModelSerializer):
    password  = serializers.CharField(write_only=True, min_length=8)
    password2 = serializers.CharField(write_only=True, label="Confirmation mot de passe")

    class Meta:
        model  = User
        fields = [
            'username', 'first_name', 'last_name', 'email',
            'telephone', 'password', 'password2',
            'cellule', 'type_membre',
            'ufr', 'specialite', 'niveau_etude', 'promo',
        ]

    def validate(self, data):
        if data['password'] != data.pop('password2'):
            raise serializers.ValidationError(
                {"password2": "Les mots de passe ne correspondent pas."}
            )
        return data

    def create(self, validated_data):
        password = validated_data.pop('password')
        # Nouveau membre = toujours role membre, admin assigne le type
        user = User(**validated_data)
        user.set_password(password)
        user.role = User.Role.MEMBRE
        user.save()
        return user


class ChangerMotDePasseSerializer(serializers.Serializer):
    ancien_mdp   = serializers.CharField(write_only=True)
    nouveau_mdp  = serializers.CharField(write_only=True, min_length=8)
    confirmation = serializers.CharField(write_only=True)

    def validate(self, data):
        if data['nouveau_mdp'] != data['confirmation']:
            raise serializers.ValidationError(
                {"confirmation": "Les mots de passe ne correspondent pas."}
            )
        return data


class TokenAvecInfosSerializer(TokenObtainPairSerializer):
    """JWT enrichi avec les infos du membre."""
    def validate(self, attrs):
        data         = super().validate(attrs)
        data['membre'] = MembreDetailSerializer(self.user).data
        return data
PYTHON
ok "accounts/serializers.py mis à jour"

# ─── 5. COTISATIONS SERIALIZERS MIS À JOUR ───────────────────
log "Mise à jour cotisations/serializers.py..."

cat > cotisations/serializers.py << 'PYTHON'
from rest_framework import serializers
from .models import Cotisation, Paiement, CotisationMensuelleConfig
from accounts.serializers import MembreListSerializer


class PaiementSerializer(serializers.ModelSerializer):
    membre_info         = MembreListSerializer(source='membre', read_only=True)
    moyen_display       = serializers.CharField(source='get_moyen_display', read_only=True)
    statut_display      = serializers.CharField(source='get_statut_display', read_only=True)
    valide_par_nom      = serializers.CharField(source='valide_par.nom_complet', read_only=True)

    class Meta:
        model  = Paiement
        fields = [
            'id', 'cotisation', 'membre', 'membre_info',
            'montant', 'moyen', 'moyen_display',
            'statut', 'statut_display',
            'reference_transaction', 'reduction_appliquee',
            'date_paiement', 'date_validation',
            'valide_par', 'valide_par_nom', 'note',
        ]
        read_only_fields = [
            'date_paiement', 'date_validation',
            'valide_par', 'statut', 'reduction_appliquee'
        ]

    def create(self, validated_data):
        validated_data['membre'] = self.context['request'].user
        return super().create(validated_data)


class ValiderPaiementSerializer(serializers.Serializer):
    statut = serializers.ChoiceField(choices=['valide', 'rejete'])
    note   = serializers.CharField(required=False, allow_blank=True)


class CotisationListSerializer(serializers.ModelSerializer):
    cellule_nom              = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    periodicite_display      = serializers.CharField(source='get_periodicite_display', read_only=True)
    type_cotisation_display  = serializers.CharField(source='get_type_cotisation_display', read_only=True)
    total_collecte           = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    nb_paiements             = serializers.IntegerField(source='nb_paiements_valides', read_only=True)
    nb_en_attente            = serializers.IntegerField(read_only=True)
    # Montant personnalisé selon le membre connecté
    montant_pour_moi         = serializers.SerializerMethodField()

    class Meta:
        model  = Cotisation
        fields = [
            'id', 'titre', 'type_cotisation', 'type_cotisation_display',
            'cellule', 'cellule_nom',
            'montant_suggere', 'reduction_membres_officiels', 'montant_pour_moi',
            'periodicite', 'periodicite_display',
            'date_limite', 'est_active', 'mois_concerne',
            'total_collecte', 'nb_paiements', 'nb_en_attente',
        ]

    def get_montant_pour_moi(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            montant = obj.montant_pour_membre(request.user)
            return str(montant) if montant is not None else None
        return None


class CotisationDetailSerializer(CotisationListSerializer):
    paiements    = PaiementSerializer(many=True, read_only=True)
    cree_par_nom = serializers.CharField(source='cree_par.nom_complet', read_only=True)

    class Meta(CotisationListSerializer.Meta):
        fields = CotisationListSerializer.Meta.fields + [
            'description', 'paiements', 'cree_par', 'cree_par_nom', 'date_creation',
        ]
        read_only_fields = ['cree_par', 'date_creation']

    def create(self, validated_data):
        validated_data['cree_par'] = self.context['request'].user
        return super().create(validated_data)


class ConfigMensuelleSerializer(serializers.ModelSerializer):
    class Meta:
        model  = CotisationMensuelleConfig
        fields = ['montant_mensuel', 'jour_rappel']
PYTHON
ok "cotisations/serializers.py mis à jour"

# ─── 6. MIGRATIONS ───────────────────────────────────────────
log "Création des migrations..."

python3 manage.py makemigrations accounts
python3 manage.py makemigrations cotisations
python3 manage.py migrate
ok "Migrations appliquées"

# ─── 7. CONFIG MENSUELLE INITIALE ────────────────────────────
log "Création de la config cotisation mensuelle..."

python3 manage.py shell << 'PYSHELL'
from cotisations.models import CotisationMensuelleConfig
config = CotisationMensuelleConfig.get()
print(f"  ✓ Config mensuelle : {config.montant_mensuel} FCFA, rappel le {config.jour_rappel} du mois")
PYSHELL
ok "Config mensuelle créée"

# ─── FIN ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Modèles v2 appliqués !                            ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Ce qui a changé :${NC}"
echo ""
echo "  accounts/User :"
echo "    + type_membre        (officiel | sympathisant)"
echo "    + date_officialisation"
echo "    + date_signature_engagement"
echo "    + est_bureau"
echo "    + poste_bureau       (11 postes du bureau)"
echo "    + dette_cotisation   (property calculée auto)"
echo "    role simplifié :     super_admin | admin_cellule | membre"
echo ""
echo "  cotisations/Cotisation :"
echo "    + type_cotisation    (mensuelle | evenement | exceptionnelle)"
echo "    + reduction_membres_officiels"
echo "    + mois_concerne      (pour cotisations mensuelles)"
echo "    + montant_pour_membre() (calcule avec réduction)"
echo ""
echo "  cotisations/Paiement :"
echo "    + reduction_appliquee (capturée au moment du paiement)"
echo ""
echo "  cotisations/CotisationMensuelleConfig :"
echo "    + Singleton : montant (1000 FCFA) + jour rappel"
echo ""
echo -e "  ${YELLOW}N'oublie pas de mettre à jour les modèles Dart Flutter aussi !${NC}"
echo ""
