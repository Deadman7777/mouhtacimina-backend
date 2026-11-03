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
    MonProfilSerializer, InscriptionSerializer, ChangerMotDePasseSerializer,
    TokenAvecInfosSerializer, AdminMembreSerializer
)
from .permissions import IsSuperAdmin, IsAdminCellule, IsAdminOrReadOnly, IsAdmin


class LoginView(TokenObtainPairView):
    """POST /api/auth/login/ — Retourne access + refresh + infos membre."""
    serializer_class = TokenAvecInfosSerializer


class CelluleViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/auth/cellules/ — Liste des cellules."""
    queryset         = Cellule.objects.all()
    serializer_class = CelluleSerializer
    permission_classes = [AllowAny]


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
        if self.action in ['update', 'partial_update']:
            return AdminMembreSerializer
        return MembreDetailSerializer

    def get_permissions(self):
        if self.action == 'list':
            return [IsAdminCellule()]
        if self.action == 'create':
            return [IsAdmin()]
        if self.action in ['destroy']:
            return [IsSuperAdmin()]
        # Modifier la fiche d'un AUTRE membre est un acte d'administration :
        # sans ce garde-fou, tout membre pouvait éditer (rôle compris) n'importe
        # quel membre actif de sa cellule, que get_queryset lui laisse voir.
        # L'édition de son propre profil passe par l'action `moi`.
        # Le bureau consulte (list), seuls les admins modifient : c'est la
        # répartition de l'app mobile, et AdminMembreSerializer verrouille
        # en plus le rôle au seul super admin.
        if self.action in ['update', 'partial_update']:
            return [IsAdmin()]
        # Pour les actions personnalisées, appliquer leur propre
        # `permission_classes`. Renvoyer IsAuthenticated ici (comme avant)
        # neutralisait ces décorateurs : n'importe quel membre pouvait
        # activer/désactiver ou migrer un autre membre de sa cellule.
        return super().get_permissions()

    def create(self, request, *args, **kwargs):
        """
        POST /api/auth/membres/ — Ajout d'un membre par un admin.
        Un admin cellule ne peut ajouter que dans sa propre cellule.
        Renvoie la fiche complète (avec l'id), pas l'écho du formulaire.
        """
        serializer = InscriptionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        extra = {}
        if request.user.role == User.Role.ADMIN_CELLULE:
            extra['cellule'] = request.user.cellule
        membre = serializer.save(**extra)
        # Comme pour un passage officiel via PATCH : la dette se calcule
        # depuis l'engagement, qu'on date donc du jour de l'ajout.
        if membre.est_officiel and not membre.date_signature_engagement:
            membre.date_signature_engagement = timezone.now().date()
            membre.date_officialisation = membre.date_officialisation or timezone.now().date()
            membre.save(update_fields=['date_signature_engagement', 'date_officialisation'])
        return Response(
            MembreDetailSerializer(membre, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['get', 'patch'], url_path='moi')
    def moi(self, request):
        """Mon profil — GET pour lire, PATCH pour modifier."""
        if request.method == 'GET':
            return Response(MembreDetailSerializer(request.user).data)

        # MonProfilSerializer, pas MembreDetailSerializer : il verrouille
        # role / cellule / type_membre / bureau contre l'auto-promotion.
        serializer = MonProfilSerializer(
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
            permission_classes=[IsAdmin], url_path='activer')
    def activer(self, request, pk=None):
        """Activer / désactiver un membre."""
        membre = self.get_object()
        membre.est_actif = not membre.est_actif
        membre.save()
        etat = "activé" if membre.est_actif else "désactivé"
        return Response({'message': f"Membre {etat}."})

    @action(detail=True, methods=['post'],
            permission_classes=[IsAdmin], url_path='migrer_cellule')
    def migrer_cellule(self, request, pk=None):
        """
        Migre un membre vers une nouvelle cellule.
        Les dettes en cours sont effacées, le nouveau barème s'applique.
        Body: { "cellule": <id_nouvelle_cellule> }
        """
        membre = self.get_object()
        nouvelle_cellule_id = request.data.get('cellule')

        if not nouvelle_cellule_id:
            return Response(
                {'error': 'La nouvelle cellule est requise.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            nouvelle_cellule = Cellule.objects.get(id=nouvelle_cellule_id)
        except Cellule.DoesNotExist:
            return Response(
                {'error': 'Cellule introuvable.'},
                status=status.HTTP_404_NOT_FOUND
            )

        if membre.cellule_id == nouvelle_cellule.id:
            return Response(
                {'error': 'Le membre est déjà dans cette cellule.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        resultat = membre.migrer_cellule(nouvelle_cellule, admin=request.user)

        return Response({
            'message': 'Migration effectuée avec succès.',
            'detail':  resultat,
            'membre':  MembreDetailSerializer(
                membre, context={'request': request}).data,
        })
