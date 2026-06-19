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
