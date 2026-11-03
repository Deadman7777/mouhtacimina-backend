"""
API publique de la vitrine — aucune authentification requise.

`authentication_classes = []` est volontaire : un visiteur (ou un membre dont
le token a expiré) ne doit jamais recevoir un 401 en consultant la vitrine.
"""
from django.utils import timezone
from rest_framework import viewsets, filters
from rest_framework.decorators import (
    api_view, authentication_classes, permission_classes
)
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend

from accounts.models import User, Cellule
from .models import Evenement
from .public_serializers import (
    EvenementPublicListSerializer, EvenementPublicDetailSerializer
)


def evenements_visibles():
    """Tout sauf les brouillons : lancés (à venir) et clôturés (passés)."""
    return Evenement.objects.exclude(
        statut=Evenement.Statut.BROUILLON
    ).select_related('cellule')


class EvenementPublicViewSet(viewsets.ReadOnlyModelViewSet):
    """
    GET /api/public/evenements/         — Événements visibles par le public
    GET /api/public/evenements/{id}/    — Détail public d'un événement

    Filtres : ?type=gamou  ?est_global=true  ?cellule=1
              ?periode=a_venir | passes
              ?search=...  ?ordering=date_debut | -date_debut
    """
    authentication_classes = []
    permission_classes     = [AllowAny]
    filter_backends  = [DjangoFilterBackend, filters.SearchFilter,
                        filters.OrderingFilter]
    filterset_fields = ['type', 'est_global', 'cellule']
    search_fields    = ['titre', 'lieu']
    ordering_fields  = ['date_debut', 'titre']
    ordering         = ['date_debut']

    def get_queryset(self):
        qs      = evenements_visibles()
        periode = self.request.query_params.get('periode')
        maintenant = timezone.now()

        if periode == 'a_venir':
            qs = qs.filter(date_debut__gte=maintenant,
                           statut=Evenement.Statut.LANCE)
        elif periode == 'passes':
            qs = qs.filter(date_debut__lt=maintenant)

        if self.action == 'retrieve':
            qs = qs.prefetch_related('cotisations')
        return qs

    def get_serializer_class(self):
        if self.action == 'retrieve':
            return EvenementPublicDetailSerializer
        return EvenementPublicListSerializer


@api_view(['GET'])
@authentication_classes([])
@permission_classes([AllowAny])
def stats_publiques(request):
    """GET /api/public/stats/ — Quelques chiffres pour la page d'accueil."""
    maintenant = timezone.now()
    visibles   = evenements_visibles()

    return Response({
        'nb_membres':    User.objects.filter(est_actif=True).count(),
        'nb_cellules':   Cellule.objects.count(),
        'nb_evenements': visibles.count(),
        'nb_a_venir':    visibles.filter(
            date_debut__gte=maintenant, statut=Evenement.Statut.LANCE
        ).count(),
    })
