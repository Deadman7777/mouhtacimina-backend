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


class PaiementAdminViewSet(viewsets.ReadOnlyModelViewSet):
    """
    GET /api/cotisations/admin/paiements/
    Tous les paiements — admin seulement
    Filtrable par statut: ?statut=en_attente
    """
    serializer_class   = PaiementSerializer
    permission_classes = [IsAdminCellule]
    filter_backends    = [DjangoFilterBackend]
    filterset_fields   = ['statut', 'moyen', 'cotisation']

    def get_queryset(self):
        user = self.request.user
        qs   = Paiement.objects.select_related(
            'membre', 'cotisation', 'valide_par'
        ).order_by('-date_paiement')

        # Admin cellule voit les paiements de sa cellule
        if user.role == 'admin_cellule':
            qs = qs.filter(
                Q(cotisation__cellule=user.cellule) |
                Q(cotisation__cellule__isnull=True)
            )
        return qs

    @action(detail=True, methods=['post'])
    def valider(self, request, pk=None):
        paiement = self.get_object()
        from django.utils import timezone
        serializer = ValiderPaiementSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        paiement.statut          = serializer.validated_data['statut']
        paiement.note            = serializer.validated_data.get('note', '')
        paiement.valide_par      = request.user
        paiement.date_validation = timezone.now()
        paiement.save()
        return Response(PaiementSerializer(paiement,
            context={'request': request}).data)


# ── Paytech ──────────────────────────────────────────────────
import uuid
import json
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from django.http import HttpResponse
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status as drf_status
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import permission_classes as pc
from .paytech_service import PaytechService


@api_view(['POST'])
@pc([IsAuthenticated])
def initier_paiement_paytech(request, cotisation_id):
    """
    POST /api/cotisations/{id}/payer-paytech/
    Initie un paiement Paytech pour une cotisation.
    Body: { "moyen": "Wave" | "Orange Money" | "Free Money" }
    """
    try:
        cotisation = Cotisation.objects.get(id=cotisation_id)
    except Cotisation.DoesNotExist:
        return Response({'error': 'Cotisation introuvable.'}, status=404)

    if not cotisation.est_active:
        return Response(
            {'error': 'Cette cotisation est fermée.'},
            status=drf_status.HTTP_400_BAD_REQUEST
        )

    membre  = request.user
    moyen   = request.data.get('moyen', 'Wave, Orange Money, Free Money')
    # Pour les cotisations mensuelles, le membre peut payer
    # n'importe quel montant (régularisation partielle ou totale)
    montant_suggere = cotisation.montant_pour_membre(membre)
    montant_recu    = request.data.get('montant')

    if montant_recu:
        montant = float(montant_recu)
    elif montant_suggere is not None:
        montant = montant_suggere
    else:
        return Response(
            {'error': 'Montant requis pour cette cotisation.'},
            status=drf_status.HTTP_400_BAD_REQUEST
        )

    # Référence unique
    ref = f'MOUHTA-{cotisation_id}-{membre.id}-{uuid.uuid4().hex[:8].upper()}'

    # Créer le paiement en base (statut en_attente)
    paiement = Paiement.objects.create(
        cotisation=cotisation,
        membre=membre,
        montant=montant,
        moyen=moyen.lower().replace(' ', '_').replace(',', '').split('_')[0]
              if ',' not in moyen else 'wave',
        statut='en_attente',
        reference_transaction=ref,
        reduction_appliquee=cotisation.reduction_membres_officiels
            if membre.est_officiel else 0,
    )

    # Appeler Paytech
    custom_field = {
        'paiement_id':   paiement.id,
        'membre_id':     membre.id,
        'cotisation_id': cotisation.id,
        'ref':           ref,
    }

    result = PaytechService.demander_paiement(
        item_name     = cotisation.titre,
        item_price    = montant,
        ref_command   = ref,
        custom_field  = custom_field,
        payment_method= moyen,
        membre        = membre,
    )

    if result.get('success') == 1:
        return Response({
            'redirect_url': result['redirect_url'],
            'token':        result.get('token'),
            'paiement_id':  paiement.id,
            'ref':          ref,
        })

    # Supprimer le paiement si Paytech échoue
    paiement.delete()
    return Response(
        {'error': result.get('message', 'Erreur Paytech')},
        status=drf_status.HTTP_502_BAD_GATEWAY
    )


@csrf_exempt
@require_POST
def paytech_ipn(request):
    """
    POST /api/payment/ipn/
    Webhook Paytech — valide automatiquement le paiement.
    """
    if not PaytechService.verifier_ipn(request):
        return HttpResponse('IPN KO - NOT FROM PAYTECH', status=403)

    type_event   = request.POST.get('type_event')
    ref_command  = request.POST.get('ref_command', '')
    custom_field_raw = request.POST.get('custom_field', '{}')
    payment_method   = request.POST.get('payment_method', '')

    try:
        custom_field = json.loads(custom_field_raw)
    except Exception:
        custom_field = {}

    paiement_id = custom_field.get('paiement_id')

    if type_event == 'sale_complete':
        try:
            paiement = Paiement.objects.get(
                id=paiement_id,
                reference_transaction=ref_command
            )
            paiement.statut          = 'valide'
            paiement.date_validation = timezone.now()
            paiement.note            = f'Validé automatiquement via Paytech ({payment_method})'
            paiement.save()

        except Paiement.DoesNotExist:
            # Chercher par référence
            try:
                paiement = Paiement.objects.get(reference_transaction=ref_command)
                paiement.statut          = 'valide'
                paiement.date_validation = timezone.now()
                paiement.save()
            except Paiement.DoesNotExist:
                pass

    elif type_event == 'sale_canceled':
        try:
            paiement = Paiement.objects.get(reference_transaction=ref_command)
            paiement.statut = 'rejete'
            paiement.note   = 'Annulé par le membre sur Paytech'
            paiement.save()
        except Paiement.DoesNotExist:
            pass

    return HttpResponse('IPN OK', status=200)
