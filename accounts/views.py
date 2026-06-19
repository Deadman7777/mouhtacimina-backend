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
        return MembreDetailSerializer

    def get_permissions(self):
        if self.action == 'list':
            return [IsAdminCellule()]
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

    @action(detail=True, methods=['post'],
            permission_classes=[IsAdminCellule], url_path='migrer_cellule')
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
