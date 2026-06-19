#!/bin/bash

# ============================================================
#   MOUHTACIMINA — Intégration Paytech
#   Lance depuis la racine du projet Django
# ============================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

NGROK_URL="https://f369-2001-4278-16-5e56-34a1-3aed-30c8-5d62.ngrok-free.app"

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   MOUHTACIMINA — Intégration Paytech                ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

[ -f "manage.py" ] || { echo "Lance depuis la racine du projet Django"; exit 1; }

# Activer virtualenv
if [ -z "$VIRTUAL_ENV" ]; then
    for venv in env venv .venv; do
        [ -d "$venv" ] && source "$venv/bin/activate" && break
    done
fi

# ─── 1. INSTALLER REQUESTS ───────────────────────────────────
log "Installation de requests..."
pip install requests --quiet
ok "requests installé"

# ─── 2. FICHIER .ENV ─────────────────────────────────────────
log "Création du fichier .env..."

cat > .env << 'EOF'
# Paytech — remplace par tes vraies clés après régénération
PAYTECH_API_KEY=METS_TA_CLE_API_ICI
PAYTECH_API_SECRET=METS_TA_CLE_SECRETE_ICI
PAYTECH_ENV=test
EOF

ok ".env créé — IMPORTANT : mets tes clés dedans !"
warn "Ouvre .env et remplace METS_TA_CLE_API_ICI par ta vraie clé"

# ─── 3. SETTINGS PAYTECH ─────────────────────────────────────
log "Ajout config Paytech dans settings.py..."

SETTINGS=$(find . -name "settings.py" \
  -not -path "*/env/*" -not -path "*/venv/*" | head -1)

python3 - << PYFIX
with open('$SETTINGS', 'r') as f:
    content = f.read()

paytech_config = '''
# ── Paytech ──────────────────────────────────────────────────
import os
PAYTECH_API_KEY    = os.environ.get('PAYTECH_API_KEY', '')
PAYTECH_API_SECRET = os.environ.get('PAYTECH_API_SECRET', '')
PAYTECH_ENV        = os.environ.get('PAYTECH_ENV', 'test')
PAYTECH_IPN_URL    = '${NGROK_URL}/api/payment/ipn/'
# URLs spéciales Flutter — ne pas changer
PAYTECH_SUCCESS_URL = 'https://paytech.sn/mobile/success'
PAYTECH_CANCEL_URL  = 'https://paytech.sn/mobile/cancel'
'''

if 'PAYTECH_API_KEY' not in content:
    content += paytech_config
    with open('$SETTINGS', 'w') as f:
        f.write(content)
    print('✅ Config Paytech ajoutée dans settings.py')
else:
    print('~ Config Paytech déjà présente')
PYFIX

ok "settings.py mis à jour"

# ─── 4. SERVICE PAYTECH ──────────────────────────────────────
log "Création cotisations/paytech_service.py..."

cat > cotisations/paytech_service.py << 'PYTHON'
import requests
import hashlib
import json
from django.conf import settings


class PaytechService:
    BASE_URL = 'https://paytech.sn/api'

    @staticmethod
    def demander_paiement(
        item_name,
        item_price,
        ref_command,
        custom_field=None,
        payment_method='Wave, Orange Money, Free Money',
        membre=None,
    ):
        """
        Crée une demande de paiement Paytech.
        Retourne le redirect_url ou None en cas d'erreur.
        """
        if custom_field is None:
            custom_field = {}

        url = f'{PaytechService.BASE_URL}/payment/request-payment'

        payload = {
            'item_name':    item_name,
            'item_price':   int(item_price),
            'currency':     'xof',
            'ref_command':  ref_command,
            'command_name': f'Paiement {item_name} — Mouhtacimina',
            'env':          settings.PAYTECH_ENV,
            'target_payment': payment_method,
            'success_url':  settings.PAYTECH_SUCCESS_URL,
            'cancel_url':   settings.PAYTECH_CANCEL_URL,
            'ipn_url':      settings.PAYTECH_IPN_URL,
            'custom_field': json.dumps(custom_field),
        }

        headers = {
            'API_KEY':    settings.PAYTECH_API_KEY,
            'API_SECRET': settings.PAYTECH_API_SECRET,
            'Content-Type': 'application/json',
        }

        try:
            response = requests.post(url, json=payload, headers=headers, timeout=30)
            data     = response.json()

            if data.get('success') == 1:
                redirect_url = data.get('redirect_url') or data.get('redirectUrl')

                # Autofill si méthode unique et membre fourni
                if membre and payment_method and ',' not in payment_method:
                    from urllib.parse import urlencode
                    phone = getattr(membre, 'telephone', '')
                    # Nettoyer le numéro (enlever espaces)
                    phone_clean = phone.replace(' ', '').replace('-', '')
                    # Ajouter indicatif si absent
                    if phone_clean and not phone_clean.startswith('+'):
                        phone_clean = f'+221{phone_clean}'

                    params = {
                        'pn':  phone_clean,
                        'nn':  phone_clean[4:] if phone_clean.startswith('+221') else phone_clean,
                        'fn':  membre.get_full_name(),
                        'tp':  payment_method,
                        'nac': 0 if payment_method == 'Carte Bancaire' else 1,
                    }
                    redirect_url += '?' + urlencode(params)

                data['redirect_url'] = redirect_url
                return data

            return {'success': 0, 'message': data.get('message', 'Erreur Paytech')}

        except requests.exceptions.RequestException as e:
            return {'success': 0, 'message': str(e)}

    @staticmethod
    def verifier_ipn(request):
        """Vérifie que l'IPN vient bien de Paytech."""
        api_key_sha256    = request.POST.get('api_key_sha256', '')
        api_secret_sha256 = request.POST.get('api_secret_sha256', '')

        expected_key    = hashlib.sha256(
            settings.PAYTECH_API_KEY.encode()
        ).hexdigest()
        expected_secret = hashlib.sha256(
            settings.PAYTECH_API_SECRET.encode()
        ).hexdigest()

        return (expected_key    == api_key_sha256 and
                expected_secret == api_secret_sha256)
PYTHON
ok "cotisations/paytech_service.py créé"

# ─── 5. VIEWS PAYTECH ────────────────────────────────────────
log "Ajout des vues Paytech dans cotisations/views.py..."

cat >> cotisations/views.py << 'PYTHON'


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
    montant = cotisation.montant_pour_membre(membre)

    if montant is None:
        montant = request.data.get('montant')
        if not montant:
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
PYTHON
ok "Vues Paytech ajoutées"

# ─── 6. URLS ─────────────────────────────────────────────────
log "Mise à jour des URLs..."

# URLs cotisations
cat > cotisations/urls.py << 'PYTHON'
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    CotisationViewSet, PaiementAdminViewSet,
    initier_paiement_paytech, paytech_ipn,
)

router = DefaultRouter()
router.register('', CotisationViewSet, basename='cotisation')

admin_router = DefaultRouter()
admin_router.register('paiements', PaiementAdminViewSet, basename='admin-paiement')

urlpatterns = [
    path('admin/', include(admin_router.urls)),
    path('<int:cotisation_id>/payer-paytech/', initier_paiement_paytech,
         name='payer-paytech'),
    path('', include(router.urls)),
]
PYTHON

# URL IPN dans urls.py principal
MAIN_URLS=$(find . -name "urls.py" \
  -not -path "*/env/*" \
  -not -path "*/migrations/*" \
  -not -path "*/accounts/*" \
  -not -path "*/evenements/*" \
  -not -path "*/cotisations/*" | head -1)

python3 - << PYFIX
with open('$MAIN_URLS', 'r') as f:
    content = f.read()

if 'paytech_ipn' not in content:
    content = content.replace(
        "from django.contrib import admin",
        "from django.contrib import admin\nfrom cotisations.views import paytech_ipn"
    )
    content = content.replace(
        "path('api/cotisations/', include('cotisations.urls')),",
        "path('api/cotisations/', include('cotisations.urls')),\n    path('api/payment/ipn/', paytech_ipn, name='paytech-ipn'),"
    )
    with open('$MAIN_URLS', 'w') as f:
        f.write(content)
    print('✅ URL IPN ajoutée dans urls.py principal')
else:
    print('~ URL IPN déjà présente')
PYFIX

ok "URLs mises à jour"

# ─── 7. VÉRIFICATION ─────────────────────────────────────────
log "Vérification Django..."
python3 manage.py check
ok "Django OK"

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Paytech Django — Done !                           ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${YELLOW}⚠️  IMPORTANT — Ouvre .env et mets tes clés :${NC}"
echo "  PAYTECH_API_KEY=ta_cle_api"
echo "  PAYTECH_API_SECRET=ta_cle_secrete"
echo ""
echo -e "  ${BLUE}Charger les variables d'env avant de lancer Django :${NC}"
echo "  export \$(cat .env | xargs)"
echo "  python manage.py runserver 0.0.0.0:8000"
echo ""
echo -e "  ${BLUE}Endpoints créés :${NC}"
echo "  POST /api/cotisations/{id}/payer-paytech/"
echo "  POST /api/payment/ipn/"
echo ""
echo -e "  ${BLUE}Prochaine étape :${NC} intégration Flutter (package paytech)"
echo ""
