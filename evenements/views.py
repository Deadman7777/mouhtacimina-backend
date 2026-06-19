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
    @action(detail=True, methods=['post'],
            permission_classes=[IsAuthenticated])
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
