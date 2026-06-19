#!/bin/bash

# ============================================================
#   MOUHTACIMINA APP — API (Serializers + ViewSets + URLs)
#   Lance depuis la racine du projet (là où est manage.py)
# ============================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   MOUHTACIMINA — API Serializers + ViewSets         ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

# Activer le virtualenv si présent
if [ -z "$VIRTUAL_ENV" ]; then
    for venv in env venv .venv; do
        [ -d "$venv" ] && source "$venv/bin/activate" && break
    done
fi

[ -f "manage.py" ] || error "Lance le script depuis la racine du projet Django (là où est manage.py)"

# ─── 1. PERMISSIONS CUSTOM ───────────────────────────────────
log "Écriture des permissions..."

mkdir -p accounts
cat > accounts/permissions.py << 'PYTHON'
from rest_framework.permissions import BasePermission


class IsSuperAdmin(BasePermission):
    """Seul le super admin peut accéder."""
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'super_admin'


class IsAdminCellule(BasePermission):
    """Admin cellule ou super admin."""
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role in [
            'super_admin', 'admin_cellule'
        ]


class IsAdminOrReadOnly(BasePermission):
    """Lecture pour tous les membres, écriture pour les admins."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        if request.method in ('GET', 'HEAD', 'OPTIONS'):
            return True
        return request.user.role in ['super_admin', 'admin_cellule']


class IsMembresMemeCellule(BasePermission):
    """Un membre ne peut voir que les membres de sa cellule (sauf admin)."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        if request.user.role in ['super_admin', 'admin_cellule']:
            return True
        return True  # filtrage fait dans le queryset

    def has_object_permission(self, request, view, obj):
        if request.user.role in ['super_admin', 'admin_cellule']:
            return True
        return obj.cellule == request.user.cellule
PYTHON
ok "accounts/permissions.py écrit"

# ─── 2. SERIALIZERS ACCOUNTS ─────────────────────────────────
log "Écriture des serializers accounts..."

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
    """Serializer léger pour les listes."""
    cellule_nom = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    role_display = serializers.CharField(source='get_role_display', read_only=True)

    class Meta:
        model  = User
        fields = [
            'id', 'first_name', 'last_name', 'email',
            'telephone', 'photo', 'role', 'role_display',
            'cellule', 'cellule_nom', 'est_actif', 'est_diplome',
            'date_adhesion',
        ]


class MembreDetailSerializer(serializers.ModelSerializer):
    """Serializer complet pour le détail/édition."""
    cellule_nom  = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    role_display = serializers.CharField(source='get_role_display', read_only=True)
    ufr_display  = serializers.CharField(source='get_ufr_display', read_only=True)
    nom_complet  = serializers.CharField(read_only=True)

    class Meta:
        model  = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 'nom_complet',
            'email', 'telephone', 'photo', 'date_naissance', 'adresse',
            'statut_matrimonial',
            # Dahira
            'role', 'role_display', 'cellule', 'cellule_nom',
            'date_adhesion', 'est_actif',
            # Académique
            'ufr', 'ufr_display', 'specialite', 'niveau_etude',
            'promo', 'est_diplome', 'annee_diplome',
        ]
        read_only_fields = ['date_adhesion', 'email']


class InscriptionSerializer(serializers.ModelSerializer):
    """Création d'un nouveau membre."""
    password  = serializers.CharField(write_only=True, min_length=8)
    password2 = serializers.CharField(write_only=True, label="Confirmation mot de passe")

    class Meta:
        model  = User
        fields = [
            'username', 'first_name', 'last_name', 'email',
            'telephone', 'password', 'password2',
            'cellule', 'role',
            'ufr', 'specialite', 'niveau_etude', 'promo',
        ]

    def validate(self, data):
        if data['password'] != data.pop('password2'):
            raise serializers.ValidationError({"password2": "Les mots de passe ne correspondent pas."})
        return data

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user


class ChangerMotDePasseSerializer(serializers.Serializer):
    ancien_mdp  = serializers.CharField(write_only=True)
    nouveau_mdp = serializers.CharField(write_only=True, min_length=8)
    confirmation = serializers.CharField(write_only=True)

    def validate(self, data):
        if data['nouveau_mdp'] != data['confirmation']:
            raise serializers.ValidationError({"confirmation": "Les mots de passe ne correspondent pas."})
        return data


class TokenAvecInfosSerializer(TokenObtainPairSerializer):
    """JWT enrichi avec les infos du membre."""
    def validate(self, attrs):
        data = super().validate(attrs)
        data['membre'] = MembreDetailSerializer(self.user).data
        return data
PYTHON
ok "accounts/serializers.py écrit"

# ─── 3. SERIALIZERS EVENEMENTS ───────────────────────────────
log "Écriture des serializers evenements..."

cat > evenements/serializers.py << 'PYTHON'
from rest_framework import serializers
from .models import Evenement, Participation, LigneBudget
from accounts.serializers import MembreListSerializer


class LigneBudgetSerializer(serializers.ModelSerializer):
    enregistre_par_nom = serializers.CharField(
        source='enregistre_par.nom_complet', read_only=True
    )

    class Meta:
        model  = LigneBudget
        fields = [
            'id', 'libelle', 'type', 'montant', 'date',
            'note', 'enregistre_par', 'enregistre_par_nom',
        ]
        read_only_fields = ['enregistre_par']

    def create(self, validated_data):
        validated_data['enregistre_par'] = self.context['request'].user
        return super().create(validated_data)


class ParticipationSerializer(serializers.ModelSerializer):
    membre_info = MembreListSerializer(source='membre', read_only=True)

    class Meta:
        model  = Participation
        fields = ['id', 'membre', 'membre_info', 'evenement', 'statut', 'date_inscription', 'note']
        read_only_fields = ['date_inscription']


class EvenementListSerializer(serializers.ModelSerializer):
    cellule_nom      = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    type_display     = serializers.CharField(source='get_type_display', read_only=True)
    statut_display   = serializers.CharField(source='get_statut_display', read_only=True)
    nb_participants  = serializers.IntegerField(read_only=True)

    class Meta:
        model  = Evenement
        fields = [
            'id', 'titre', 'type', 'type_display',
            'statut', 'statut_display', 'est_global',
            'cellule', 'cellule_nom', 'lieu',
            'date_debut', 'date_fin', 'budget_prevu',
            'nb_participants',
        ]


class EvenementDetailSerializer(serializers.ModelSerializer):
    cellule_nom    = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    type_display   = serializers.CharField(source='get_type_display', read_only=True)
    statut_display = serializers.CharField(source='get_statut_display', read_only=True)
    cree_par_nom   = serializers.CharField(source='cree_par.nom_complet', read_only=True)
    lignes_budget  = LigneBudgetSerializer(many=True, read_only=True)
    nb_participants = serializers.IntegerField(read_only=True)
    budget_reel    = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model  = Evenement
        fields = [
            'id', 'titre', 'description', 'type', 'type_display',
            'statut', 'statut_display', 'est_global',
            'cellule', 'cellule_nom', 'lieu',
            'date_debut', 'date_fin', 'budget_prevu', 'budget_reel',
            'nb_participants', 'lignes_budget',
            'cree_par', 'cree_par_nom',
            'date_creation', 'date_modification',
        ]
        read_only_fields = ['cree_par', 'date_creation', 'date_modification', 'statut']

    def create(self, validated_data):
        validated_data['cree_par'] = self.context['request'].user
        return super().create(validated_data)


class BilanSerializer(serializers.Serializer):
    """Bilan complet d'un événement."""
    evenement_id   = serializers.IntegerField()
    titre          = serializers.CharField()
    statut         = serializers.CharField()
    nb_inscrits    = serializers.IntegerField()
    nb_presents    = serializers.IntegerField()
    nb_absents     = serializers.IntegerField()
    taux_presence  = serializers.FloatField()
    budget_prevu   = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_recettes = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_depenses = serializers.DecimalField(max_digits=12, decimal_places=2)
    solde          = serializers.DecimalField(max_digits=12, decimal_places=2)
    lignes_budget  = LigneBudgetSerializer(many=True)
PYTHON
ok "evenements/serializers.py écrit"

# ─── 4. SERIALIZERS COTISATIONS ──────────────────────────────
log "Écriture des serializers cotisations..."

cat > cotisations/serializers.py << 'PYTHON'
from rest_framework import serializers
from .models import Cotisation, Paiement
from accounts.serializers import MembreListSerializer


class PaiementSerializer(serializers.ModelSerializer):
    membre_info    = MembreListSerializer(source='membre', read_only=True)
    moyen_display  = serializers.CharField(source='get_moyen_display', read_only=True)
    statut_display = serializers.CharField(source='get_statut_display', read_only=True)
    valide_par_nom = serializers.CharField(source='valide_par.nom_complet', read_only=True)

    class Meta:
        model  = Paiement
        fields = [
            'id', 'cotisation', 'membre', 'membre_info',
            'montant', 'moyen', 'moyen_display',
            'statut', 'statut_display',
            'reference_transaction',
            'date_paiement', 'date_validation',
            'valide_par', 'valide_par_nom', 'note',
        ]
        read_only_fields = ['date_paiement', 'date_validation', 'valide_par', 'statut']

    def create(self, validated_data):
        # Le membre est automatiquement l'utilisateur connecté
        validated_data['membre'] = self.context['request'].user
        return super().create(validated_data)


class ValiderPaiementSerializer(serializers.Serializer):
    """Pour qu'un admin valide ou rejette un paiement."""
    statut = serializers.ChoiceField(choices=['valide', 'rejete'])
    note   = serializers.CharField(required=False, allow_blank=True)


class CotisationListSerializer(serializers.ModelSerializer):
    cellule_nom        = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    periodicite_display = serializers.CharField(source='get_periodicite_display', read_only=True)
    total_collecte     = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    nb_paiements       = serializers.SerializerMethodField()

    class Meta:
        model  = Cotisation
        fields = [
            'id', 'titre', 'cellule', 'cellule_nom',
            'montant_suggere', 'periodicite', 'periodicite_display',
            'date_limite', 'est_active',
            'total_collecte', 'nb_paiements',
        ]

    def get_nb_paiements(self, obj):
        return obj.paiements.filter(statut='valide').count()


class CotisationDetailSerializer(serializers.ModelSerializer):
    cellule_nom         = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    periodicite_display = serializers.CharField(source='get_periodicite_display', read_only=True)
    total_collecte      = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    paiements           = PaiementSerializer(many=True, read_only=True)
    cree_par_nom        = serializers.CharField(source='cree_par.nom_complet', read_only=True)

    class Meta:
        model  = Cotisation
        fields = [
            'id', 'titre', 'description',
            'cellule', 'cellule_nom',
            'montant_suggere', 'periodicite', 'periodicite_display',
            'date_limite', 'est_active', 'total_collecte',
            'paiements', 'cree_par', 'cree_par_nom', 'date_creation',
        ]
        read_only_fields = ['cree_par', 'date_creation']

    def create(self, validated_data):
        validated_data['cree_par'] = self.context['request'].user
        return super().create(validated_data)
PYTHON
ok "cotisations/serializers.py écrit"

# ─── 5. VIEWSETS ACCOUNTS ────────────────────────────────────
log "Écriture des ViewSets accounts..."

cat > accounts/views.py << 'PYTHON'
from django.utils import timezone
from rest_framework import viewsets, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.views import TokenObtainPairView
from django_filters.rest_framework import DjangoFilterBackend

from .models import User, Cellule
from .serializers import (
    CelluleSerializer, MembreListSerializer, MembreDetailSerializer,
    InscriptionSerializer, ChangerMotDePasseSerializer, TokenAvecInfosSerializer
)
from .permissions import IsSuperAdmin, IsAdminCellule, IsAdminOrReadOnly


class LoginView(TokenObtainPairView):
    """POST /api/auth/login/ — Retourne access + refresh + infos membre."""
    serializer_class = TokenAvecInfosSerializer


class CelluleViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/auth/cellules/ — Liste des cellules."""
    queryset         = Cellule.objects.all()
    serializer_class = CelluleSerializer
    permission_classes = [IsAuthenticated]


class MembreViewSet(viewsets.ModelViewSet):
    """
    GET    /api/auth/membres/          — Liste membres
    POST   /api/auth/membres/          — Créer membre (admin)
    GET    /api/auth/membres/{id}/     — Détail membre
    PATCH  /api/auth/membres/{id}/     — Modifier membre
    GET    /api/auth/membres/moi/      — Mon profil
    POST   /api/auth/membres/moi/changer_mdp/ — Changer mon mot de passe
    """
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['cellule', 'role', 'est_actif', 'est_diplome', 'ufr']
    search_fields    = ['first_name', 'last_name', 'email', 'telephone']
    ordering_fields  = ['first_name', 'last_name', 'date_adhesion']
    ordering         = ['first_name']

    def get_queryset(self):
        user = self.request.user
        # Super admin voit tout
        if user.role == 'super_admin':
            return User.objects.all().select_related('cellule')
        # Admin cellule voit sa cellule
        if user.role == 'admin_cellule':
            return User.objects.filter(cellule=user.cellule).select_related('cellule')
        # Membre voit sa cellule
        return User.objects.filter(cellule=user.cellule, est_actif=True).select_related('cellule')

    def get_serializer_class(self):
        if self.action == 'list':
            return MembreListSerializer
        if self.action == 'create':
            return InscriptionSerializer
        return MembreDetailSerializer

    def get_permissions(self):
        if self.action == 'create':
            return [IsAdminCellule()]
        if self.action in ['destroy']:
            return [IsSuperAdmin()]
        return [IsAuthenticated()]

    @action(detail=False, methods=['get', 'patch'], url_path='moi')
    def moi(self, request):
        """Mon profil — GET pour lire, PATCH pour modifier."""
        if request.method == 'GET':
            return Response(MembreDetailSerializer(request.user).data)

        serializer = MembreDetailSerializer(
            request.user, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    @action(detail=False, methods=['post'], url_path='moi/changer-mdp')
    def changer_mdp(self, request):
        """Changer son propre mot de passe."""
        serializer = ChangerMotDePasseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        if not request.user.check_password(serializer.validated_data['ancien_mdp']):
            return Response(
                {'ancien_mdp': 'Mot de passe incorrect.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        request.user.set_password(serializer.validated_data['nouveau_mdp'])
        request.user.save()
        return Response({'message': 'Mot de passe modifié avec succès.'})

    @action(detail=False, methods=['post'], url_path='inscrire',
            permission_classes=[AllowAny])
    def inscrire(self, request):
        """POST /api/auth/membres/inscrire/ — Auto-inscription (sans admin)."""
        serializer = InscriptionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # Forcer le rôle membre_actif pour l'auto-inscription
        membre = serializer.save(role='membre_actif')
        return Response(
            MembreDetailSerializer(membre).data,
            status=status.HTTP_201_CREATED
        )

    @action(detail=True, methods=['post'],
            permission_classes=[IsAdminCellule], url_path='activer')
    def activer(self, request, pk=None):
        """Activer / désactiver un membre."""
        membre = self.get_object()
        membre.est_actif = not membre.est_actif
        membre.save()
        etat = "activé" if membre.est_actif else "désactivé"
        return Response({'message': f"Membre {etat}."})
PYTHON
ok "accounts/views.py écrit"

# ─── 6. VIEWSETS EVENEMENTS ──────────────────────────────────
log "Écriture des ViewSets evenements..."

cat > evenements/views.py << 'PYTHON'
from django.utils import timezone
from django.db.models import Sum, Count, Q
from rest_framework import viewsets, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django_filters.rest_framework import DjangoFilterBackend

from .models import Evenement, Participation, LigneBudget
from .serializers import (
    EvenementListSerializer, EvenementDetailSerializer,
    ParticipationSerializer, LigneBudgetSerializer, BilanSerializer
)
from accounts.permissions import IsAdminOrReadOnly, IsAdminCellule


class EvenementViewSet(viewsets.ModelViewSet):
    """
    GET    /api/evenements/                     — Liste événements
    POST   /api/evenements/                     — Créer (admin)
    GET    /api/evenements/{id}/                — Détail
    PATCH  /api/evenements/{id}/                — Modifier (admin)
    POST   /api/evenements/{id}/lancer/         — Lancer l'événement
    POST   /api/evenements/{id}/cloturer/       — Clôturer
    GET    /api/evenements/{id}/bilan/          — Bilan complet
    POST   /api/evenements/{id}/participer/     — S'inscrire
    GET    /api/evenements/{id}/participants/   — Liste participants
    GET    /api/evenements/{id}/budget/         — Lignes budget
    POST   /api/evenements/{id}/budget/         — Ajouter ligne budget
    """
    filter_backends  = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['statut', 'type', 'est_global', 'cellule']
    search_fields    = ['titre', 'lieu']
    ordering_fields  = ['date_debut', 'titre']
    ordering         = ['-date_debut']
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        user = self.request.user
        qs   = Evenement.objects.select_related('cellule', 'cree_par') \
                                .prefetch_related('participations', 'lignes_budget')

        # Super admin voit tout
        if user.role == 'super_admin':
            return qs

        # Les autres voient les événements globaux + ceux de leur cellule
        return qs.filter(Q(est_global=True) | Q(cellule=user.cellule))

    def get_serializer_class(self):
        if self.action == 'list':
            return EvenementListSerializer
        return EvenementDetailSerializer

    # ── Actions de cycle de vie ──────────────────────────────
    @action(detail=True, methods=['post'], permission_classes=[IsAdminCellule])
    def lancer(self, request, pk=None):
        evt = self.get_object()
        if evt.statut != 'brouillon':
            return Response(
                {'error': f"Impossible de lancer un événement en statut '{evt.statut}'."},
                status=status.HTTP_400_BAD_REQUEST
            )
        evt.statut = 'lance'
        evt.save()
        return Response({'message': f"Événement '{evt.titre}' lancé.", 'statut': 'lance'})

    @action(detail=True, methods=['post'], permission_classes=[IsAdminCellule])
    def cloturer(self, request, pk=None):
        evt = self.get_object()
        if evt.statut != 'lance':
            return Response(
                {'error': "Seul un événement lancé peut être clôturé."},
                status=status.HTTP_400_BAD_REQUEST
            )
        evt.statut = 'cloture'
        evt.date_fin = timezone.now()
        evt.save()
        return Response({'message': f"Événement '{evt.titre}' clôturé.", 'statut': 'cloture'})

    @action(detail=True, methods=['get'])
    def bilan(self, request, pk=None):
        evt          = self.get_object()
        participations = evt.participations.all()
        lignes        = evt.lignes_budget.all()

        recettes = lignes.filter(type='recette').aggregate(t=Sum('montant'))['t'] or 0
        depenses = lignes.filter(type='depense').aggregate(t=Sum('montant'))['t'] or 0

        nb_inscrits = participations.count()
        nb_presents = participations.filter(statut='present').count()
        nb_absents  = participations.filter(statut='absent').count()

        data = {
            'evenement_id'  : evt.id,
            'titre'         : evt.titre,
            'statut'        : evt.get_statut_display(),
            'nb_inscrits'   : nb_inscrits,
            'nb_presents'   : nb_presents,
            'nb_absents'    : nb_absents,
            'taux_presence' : round((nb_presents / nb_inscrits * 100) if nb_inscrits else 0, 1),
            'budget_prevu'  : evt.budget_prevu,
            'total_recettes': recettes,
            'total_depenses': depenses,
            'solde'         : recettes - depenses,
            'lignes_budget' : LigneBudgetSerializer(lignes, many=True).data,
        }
        return Response(data)

    # ── Participation ────────────────────────────────────────
    @action(detail=True, methods=['post'])
    def participer(self, request, pk=None):
        evt = self.get_object()
        if evt.statut != 'lance':
            return Response(
                {'error': "Cet événement n'est pas ouvert aux inscriptions."},
                status=status.HTTP_400_BAD_REQUEST
            )
        participation, created = Participation.objects.get_or_create(
            membre=request.user, evenement=evt
        )
        if not created:
            return Response(
                {'message': 'Vous êtes déjà inscrit à cet événement.'},
                status=status.HTTP_200_OK
            )
        return Response(
            ParticipationSerializer(participation).data,
            status=status.HTTP_201_CREATED
        )

    @action(detail=True, methods=['get'], permission_classes=[IsAdminCellule])
    def participants(self, request, pk=None):
        evt  = self.get_object()
        qs   = evt.participations.select_related('membre', 'membre__cellule')
        data = ParticipationSerializer(qs, many=True).data
        return Response(data)

    @action(detail=True, methods=['patch'],
            url_path='participants/(?P<participation_id>[^/.]+)/presence',
            permission_classes=[IsAdminCellule])
    def marquer_presence(self, request, pk=None, participation_id=None):
        """PATCH /api/evenements/{id}/participants/{participation_id}/presence"""
        try:
            p = Participation.objects.get(id=participation_id, evenement_id=pk)
        except Participation.DoesNotExist:
            return Response({'error': 'Participation introuvable.'}, status=404)
        p.statut = request.data.get('statut', 'present')
        p.save()
        return Response(ParticipationSerializer(p).data)

    # ── Budget ───────────────────────────────────────────────
    @action(detail=True, methods=['get', 'post'],
            permission_classes=[IsAdminCellule])
    def budget(self, request, pk=None):
        evt = self.get_object()

        if request.method == 'GET':
            lignes = evt.lignes_budget.all()
            return Response(LigneBudgetSerializer(lignes, many=True).data)

        serializer = LigneBudgetSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        serializer.save(evenement=evt)
        return Response(serializer.data, status=status.HTTP_201_CREATED)
PYTHON
ok "evenements/views.py écrit"

# ─── 7. VIEWSETS COTISATIONS ─────────────────────────────────
log "Écriture des ViewSets cotisations..."

cat > cotisations/views.py << 'PYTHON'
from django.utils import timezone
from rest_framework import viewsets, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django_filters.rest_framework import DjangoFilterBackend
from django.db.models import Q

from .models import Cotisation, Paiement
from .serializers import (
    CotisationListSerializer, CotisationDetailSerializer,
    PaiementSerializer, ValiderPaiementSerializer
)
from accounts.permissions import IsAdminOrReadOnly, IsAdminCellule


class CotisationViewSet(viewsets.ModelViewSet):
    """
    GET    /api/cotisations/                         — Liste campagnes
    POST   /api/cotisations/                         — Créer campagne (admin)
    GET    /api/cotisations/{id}/                    — Détail
    POST   /api/cotisations/{id}/payer/              — Envoyer un paiement
    GET    /api/cotisations/{id}/paiements/          — Liste paiements (admin)
    POST   /api/cotisations/{id}/paiements/{pid}/valider/ — Valider/rejeter
    GET    /api/cotisations/mes-paiements/           — Mes paiements
    """
    filter_backends    = [DjangoFilterBackend, filters.SearchFilter]
    filterset_fields   = ['est_active', 'periodicite', 'cellule']
    search_fields      = ['titre']
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        user = self.request.user
        qs   = Cotisation.objects.select_related('cellule', 'cree_par') \
                                 .prefetch_related('paiements')

        if user.role == 'super_admin':
            return qs
        # Membre voit les cotisations de sa cellule + globales (cellule=null)
        return qs.filter(Q(cellule=user.cellule) | Q(cellule__isnull=True), est_active=True)

    def get_serializer_class(self):
        if self.action == 'list':
            return CotisationListSerializer
        return CotisationDetailSerializer

    # ── Payer ────────────────────────────────────────────────
    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated])
    def payer(self, request, pk=None):
        """Un membre enregistre son paiement (en attente de validation admin)."""
        cotisation = self.get_object()

        if not cotisation.est_active:
            return Response(
                {'error': 'Cette campagne de cotisation est fermée.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Vérifier si déjà payé et validé
        deja_valide = Paiement.objects.filter(
            cotisation=cotisation,
            membre=request.user,
            statut='valide'
        ).exists()
        if deja_valide:
            return Response(
                {'error': 'Vous avez déjà un paiement validé pour cette cotisation.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        serializer = PaiementSerializer(
            data={**request.data, 'cotisation': cotisation.id},
            context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        paiement = serializer.save()
        return Response(
            PaiementSerializer(paiement, context={'request': request}).data,
            status=status.HTTP_201_CREATED
        )

    # ── Liste paiements ──────────────────────────────────────
    @action(detail=True, methods=['get'], permission_classes=[IsAdminCellule])
    def paiements(self, request, pk=None):
        cotisation = self.get_object()
        statut     = request.query_params.get('statut')
        qs         = cotisation.paiements.select_related('membre', 'valide_par')

        if statut:
            qs = qs.filter(statut=statut)

        return Response(PaiementSerializer(qs, many=True, context={'request': request}).data)

    # ── Valider / Rejeter un paiement ────────────────────────
    @action(
        detail=True,
        methods=['post'],
        url_path='paiements/(?P<paiement_id>[^/.]+)/valider',
        permission_classes=[IsAdminCellule]
    )
    def valider_paiement(self, request, pk=None, paiement_id=None):
        try:
            paiement = Paiement.objects.get(id=paiement_id, cotisation_id=pk)
        except Paiement.DoesNotExist:
            return Response({'error': 'Paiement introuvable.'}, status=404)

        serializer = ValiderPaiementSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        paiement.statut       = serializer.validated_data['statut']
        paiement.note         = serializer.validated_data.get('note', '')
        paiement.valide_par   = request.user
        paiement.date_validation = timezone.now()
        paiement.save()

        action_str = "validé" if paiement.statut == 'valide' else "rejeté"
        return Response({
            'message' : f"Paiement {action_str}.",
            'paiement': PaiementSerializer(paiement, context={'request': request}).data
        })

    # ── Mes paiements ────────────────────────────────────────
    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated],
            url_path='mes-paiements')
    def mes_paiements(self, request):
        """GET /api/cotisations/mes-paiements/ — Historique de mes paiements."""
        paiements = Paiement.objects.filter(
            membre=request.user
        ).select_related('cotisation').order_by('-date_paiement')

        return Response(
            PaiementSerializer(paiements, many=True, context={'request': request}).data
        )
PYTHON
ok "cotisations/views.py écrit"

# ─── 8. URLS ─────────────────────────────────────────────────
log "Écriture des URLs..."

cat > accounts/urls.py << 'PYTHON'
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import LoginView, MembreViewSet, CelluleViewSet

router = DefaultRouter()
router.register('membres',  MembreViewSet,  basename='membre')
router.register('cellules', CelluleViewSet, basename='cellule')

urlpatterns = [
    path('login/',   LoginView.as_view(),        name='login'),
    path('refresh/', TokenRefreshView.as_view(),  name='token_refresh'),
    path('',         include(router.urls)),
]
PYTHON

cat > evenements/urls.py << 'PYTHON'
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import EvenementViewSet

router = DefaultRouter()
router.register('', EvenementViewSet, basename='evenement')

urlpatterns = [
    path('', include(router.urls)),
]
PYTHON

cat > cotisations/urls.py << 'PYTHON'
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import CotisationViewSet

router = DefaultRouter()
router.register('', CotisationViewSet, basename='cotisation')

urlpatterns = [
    path('', include(router.urls)),
]
PYTHON
ok "URLs écrites"

# ─── 9. VÉRIFICATION FINALE ──────────────────────────────────
log "Vérification de la configuration..."
python3 manage.py check --deploy 2>/dev/null || python3 manage.py check

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   API prête !                                        ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Lancer le serveur :${NC}    python manage.py runserver"
echo ""
echo -e "  ${GREEN}Endpoints disponibles :${NC}"
echo "  POST   /api/auth/login/"
echo "  POST   /api/auth/refresh/"
echo "  GET    /api/auth/membres/"
echo "  POST   /api/auth/membres/inscrire/"
echo "  GET    /api/auth/membres/moi/"
echo "  GET    /api/auth/cellules/"
echo ""
echo "  GET    /api/evenements/"
echo "  POST   /api/evenements/{id}/lancer/"
echo "  POST   /api/evenements/{id}/cloturer/"
echo "  GET    /api/evenements/{id}/bilan/"
echo "  POST   /api/evenements/{id}/participer/"
echo "  GET    /api/evenements/{id}/budget/"
echo ""
echo "  GET    /api/cotisations/"
echo "  POST   /api/cotisations/{id}/payer/"
echo "  GET    /api/cotisations/mes-paiements/"
echo "  POST   /api/cotisations/{id}/paiements/{pid}/valider/"
echo ""
echo -e "  ${BLUE}Swagger UI :${NC}           http://127.0.0.1:8000/api/docs/"
echo ""
