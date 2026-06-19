#!/bin/bash

# ============================================================
#   MOUHTACIMINA — Connexion Backend + Données de test
#   Lance depuis la racine du projet Django
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
echo -e "${GREEN}   MOUHTACIMINA — Connexion Backend                  ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

[ -f "manage.py" ] || error "Lance depuis la racine du projet Django"

# Activer virtualenv
if [ -z "$VIRTUAL_ENV" ]; then
    for venv in env venv .venv; do
        [ -d "$venv" ] && source "$venv/bin/activate" && break
    done
fi

# ─── 1. VÉRIFIER SETTINGS ────────────────────────────────────
log "Vérification de settings.py..."

SETTINGS=$(find . -name "settings.py" \
  -not -path "*/env/*" -not -path "*/venv/*" | head -1)

# CORS — autoriser l'émulateur Android
if ! grep -q "CORS_ALLOW_ALL_ORIGINS" "$SETTINGS"; then
    cat >> "$SETTINGS" << 'CONF'

# ── CORS Flutter ─────────────────────────────────────────────
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOWED_ORIGINS = [
    "http://10.0.2.2:8000",   # Émulateur Android
    "http://localhost:8000",   # iOS Simulator
    "http://127.0.0.1:8000",
]
CONF
    ok "CORS configuré"
else
    warn "CORS déjà configuré"
fi

# Ajouter corsheaders middleware si absent
if ! grep -q "corsheaders.middleware" "$SETTINGS"; then
    # Insérer CorsMiddleware en premier dans MIDDLEWARE
    sed -i "s/'django.middleware.security.SecurityMiddleware',/'corsheaders.middleware.CorsMiddleware',\n    'django.middleware.security.SecurityMiddleware',/" \
        "$SETTINGS" 2>/dev/null || \
    warn "Ajoute manuellement 'corsheaders.middleware.CorsMiddleware' EN PREMIER dans MIDDLEWARE"
    ok "CorsMiddleware ajouté"
fi

# Vérifier INSTALLED_APPS
for app in corsheaders rest_framework rest_framework_simplejwt \
           accounts evenements cotisations; do
    if ! grep -q "'$app'" "$SETTINGS" && ! grep -q "\"$app\"" "$SETTINGS"; then
        echo "    '$app'," >> "$SETTINGS"
        warn "App '$app' ajoutée manuellement — vérifie l'ordre dans INSTALLED_APPS"
    fi
done

ok "Settings vérifié"

# ─── 2. URLS PRINCIPALES ─────────────────────────────────────
log "Mise à jour urls.py principal..."

URLS_FILE=$(find . -name "urls.py" \
  -not -path "*/env/*" \
  -not -path "*/migrations/*" \
  -not -path "*/accounts/*" \
  -not -path "*/evenements/*" \
  -not -path "*/cotisations/*" | head -1)

cat > "$URLS_FILE" << 'PYTHON'
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path('admin/', admin.site.urls),

    # Auth & membres
    path('api/auth/',        include('accounts.urls')),

    # Événements
    path('api/evenements/',  include('evenements.urls')),

    # Cotisations
    path('api/cotisations/', include('cotisations.urls')),

    # Docs Swagger
    path('api/schema/',  SpectacularAPIView.as_view(),          name='schema'),
    path('api/docs/',    SpectacularSwaggerView.as_view(
                           url_name='schema'), name='swagger-ui'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
PYTHON
ok "urls.py principal mis à jour"

# ─── 3. VIEWS COTISATIONS — endpoint admin paiements ─────────
log "Ajout endpoint admin pour tous les paiements..."

cat >> cotisations/views.py << 'PYTHON'


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
PYTHON
ok "PaiementAdminViewSet ajouté"

# ─── 4. URLS COTISATIONS — ajouter admin paiements ───────────
cat > cotisations/urls.py << 'PYTHON'
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import CotisationViewSet, PaiementAdminViewSet

router = DefaultRouter()
router.register('', CotisationViewSet, basename='cotisation')

# Router séparé pour admin paiements
admin_router = DefaultRouter()
admin_router.register('paiements', PaiementAdminViewSet, basename='admin-paiement')

urlpatterns = [
    path('admin/', include(admin_router.urls)),
    path('', include(router.urls)),
]
PYTHON
ok "cotisations/urls.py mis à jour"

# ─── 5. MIGRATIONS PROPRES ───────────────────────────────────
log "Vérification et application des migrations..."
python3 manage.py migrate --run-syncdb 2>/dev/null || python3 manage.py migrate
ok "Migrations OK"

# ─── 6. DONNÉES DE TEST ──────────────────────────────────────
log "Création des données de test..."

python3 manage.py shell << 'PYSHELL'
from django.utils import timezone
from datetime import date, timedelta
from decimal import Decimal

print("\n📦 Création des données de test...\n")

# ── Cellules ─────────────────────────────────────────────────
from accounts.models import Cellule, User

cellules = {}
for nom, desc in [
    ('UGB',      'Cellule mère — Saint-Louis'),
    ('DAKAR',    'Cellule Dakar'),
    ('NORD',     'Cellule Nord'),
    ('DIASPORA', 'Cellule Diaspora'),
]:
    obj, created = Cellule.objects.get_or_create(
        nom=nom, defaults={'description': desc})
    cellules[nom] = obj
    print(f"  {'✓ Créée' if created else '~ Existe'} : Cellule {nom}")

# ── Super Admin ───────────────────────────────────────────────
admin, created = User.objects.get_or_create(
    email='admin@mouhtacimina.sn',
    defaults={
        'username':      'superadmin',
        'first_name':    'Mouhtacimina',
        'last_name':     'Admin',
        'role':          'super_admin',
        'type_membre':   'officiel',
        'cellule':       cellules['UGB'],
        'est_bureau':    True,
        'poste_bureau':  'president',
        'date_signature_engagement': date.today() - timedelta(days=365),
        'is_staff':      True,
        'is_superuser':  True,
    }
)
if created:
    admin.set_password('admin1234')
    admin.save()
    print(f"  ✓ Super Admin créé : admin@mouhtacimina.sn / admin1234")
else:
    print(f"  ~ Super Admin existe déjà")

# ── Admin Cellule Dakar ───────────────────────────────────────
admin_dakar, created = User.objects.get_or_create(
    email='admin.dakar@mouhtacimina.sn',
    defaults={
        'username':      'admin_dakar',
        'first_name':    'Mamadou',
        'last_name':     'Diop',
        'role':          'admin_cellule',
        'type_membre':   'officiel',
        'cellule':       cellules['DAKAR'],
        'est_bureau':    True,
        'poste_bureau':  'sg',
        'date_signature_engagement': date.today() - timedelta(days=180),
    }
)
if created:
    admin_dakar.set_password('admin1234')
    admin_dakar.save()
    print(f"  ✓ Admin Dakar créé : admin.dakar@mouhtacimina.sn / admin1234")
else:
    print(f"  ~ Admin Dakar existe déjà")

# ── Membres officiels UGB ─────────────────────────────────────
membres_data = [
    {
        'email':      'oumar.ba@mouhtacimina.sn',
        'username':   'oumar_ba',
        'first_name': 'Oumar',
        'last_name':  'Ba',
        'type_membre':'officiel',
        'cellule':    cellules['UGB'],
        'ufr':        'SAT',
        'specialite': 'Informatique',
        'niveau_etude':'L3',
        'promo':      '2026',
        'est_bureau': True,
        'poste_bureau':'tresorier',
        'date_signature_engagement': date.today() - timedelta(days=400),
    },
    {
        'email':      'fatou.sow@mouhtacimina.sn',
        'username':   'fatou_sow',
        'first_name': 'Fatou',
        'last_name':  'Sow',
        'type_membre':'officiel',
        'cellule':    cellules['UGB'],
        'ufr':        'SEG',
        'specialite': 'Finance',
        'niveau_etude':'M1',
        'promo':      '2025',
        'est_bureau': True,
        'poste_bureau':'pdte_finance',
        'date_signature_engagement': date.today() - timedelta(days=300),
    },
    {
        'email':      'ibrahima.ndiaye@mouhtacimina.sn',
        'username':   'ibrahima_ndiaye',
        'first_name': 'Ibrahima',
        'last_name':  'Ndiaye',
        'type_membre':'officiel',
        'cellule':    cellules['UGB'],
        'ufr':        'SJP',
        'specialite': 'Droit privé',
        'niveau_etude':'L2',
        'promo':      '2027',
        'date_signature_engagement': date.today() - timedelta(days=90),
    },
    {
        'email':      'aminata.fall@mouhtacimina.sn',
        'username':   'aminata_fall',
        'first_name': 'Aminata',
        'last_name':  'Fall',
        'type_membre':'sympathisant',
        'cellule':    cellules['DAKAR'],
        'ufr':        'LSH',
        'specialite': 'Anglais',
        'niveau_etude':'L3',
        'promo':      '2026',
    },
    {
        'email':      'moussa.gueye@mouhtacimina.sn',
        'username':   'moussa_gueye',
        'first_name': 'Moussa',
        'last_name':  'Gueye',
        'type_membre':'officiel',
        'cellule':    cellules['DAKAR'],
        'ufr':        '2S',
        'specialite': 'Médecine',
        'niveau_etude':'M2',
        'promo':      '2024',
        'est_diplome': True,
        'annee_diplome': '2024',
        'date_signature_engagement': date.today() - timedelta(days=500),
    },
    {
        'email':      'aissatou.barry@mouhtacimina.sn',
        'username':   'aissatou_barry',
        'first_name': 'Aïssatou',
        'last_name':  'Barry',
        'type_membre':'sympathisant',
        'cellule':    cellules['NORD'],
    },
]

for data in membres_data:
    m, created = User.objects.get_or_create(
        email=data['email'],
        defaults={**data, 'role': 'membre'}
    )
    if created:
        m.set_password('membre1234')
        m.save()
        print(f"  ✓ Membre : {m.get_full_name()} ({m.type_membre})")
    else:
        print(f"  ~ Existe : {m.get_full_name()}")

# ── Événements ────────────────────────────────────────────────
from evenements.models import Evenement, Participation, LigneBudget

# Gamou global (lancé)
gamou, created = Evenement.objects.get_or_create(
    titre='Gamou Annuel 2026',
    defaults={
        'description': 'Grand rassemblement annuel de toutes les cellules '
                       'du Dahira Mouhtacimina pour célébrer le Mawlid.',
        'type':        'gamou',
        'statut':      'lance',
        'est_global':  True,
        'lieu':        'Grande Mosquée de Saint-Louis',
        'date_debut':  timezone.now() + timedelta(days=30),
        'budget_prevu': Decimal('500000'),
        'cree_par':    admin,
    }
)
print(f"\n  {'✓ Créé' if created else '~ Existe'} : Événement Gamou 2026")

if created:
    # Lignes budget gamou
    LigneBudget.objects.create(
        evenement=gamou, libelle='Cotisations membres',
        type='recette', montant=Decimal('150000'),
        date=date.today(), enregistre_par=admin
    )
    LigneBudget.objects.create(
        evenement=gamou, libelle='Don du bureau',
        type='recette', montant=Decimal('50000'),
        date=date.today(), enregistre_par=admin
    )
    LigneBudget.objects.create(
        evenement=gamou, libelle='Location salle',
        type='depense', montant=Decimal('80000'),
        date=date.today(), enregistre_par=admin
    )

# Réunion UGB (brouillon)
reunion, created = Evenement.objects.get_or_create(
    titre='Réunion mensuelle — UGB',
    defaults={
        'description': 'Réunion mensuelle de la cellule UGB.',
        'type':        'reunion',
        'statut':      'brouillon',
        'est_global':  False,
        'cellule':     cellules['UGB'],
        'lieu':        'Salle C001 — UFR SAT',
        'date_debut':  timezone.now() + timedelta(days=7),
        'budget_prevu': Decimal('0'),
        'cree_par':    admin,
    }
)
print(f"  {'✓ Créé' if created else '~ Existe'} : Réunion UGB")

# Formation clôturée
formation, created = Evenement.objects.get_or_create(
    titre='Formation leadership islamique',
    defaults={
        'description': 'Formation sur le leadership et les valeurs islamiques.',
        'type':        'formation',
        'statut':      'cloture',
        'est_global':  False,
        'cellule':     cellules['DAKAR'],
        'lieu':        'Centre culturel de Dakar',
        'date_debut':  timezone.now() - timedelta(days=14),
        'date_fin':    timezone.now() - timedelta(days=13),
        'budget_prevu': Decimal('75000'),
        'cree_par':    admin,
    }
)
print(f"  {'✓ Créé' if created else '~ Existe'} : Formation Dakar")

if created:
    LigneBudget.objects.create(
        evenement=formation, libelle='Collecte membres',
        type='recette', montant=Decimal('60000'),
        date=date.today() - timedelta(days=14), enregistre_par=admin
    )
    LigneBudget.objects.create(
        evenement=formation, libelle='Matériel formation',
        type='depense', montant=Decimal('25000'),
        date=date.today() - timedelta(days=14), enregistre_par=admin
    )
    LigneBudget.objects.create(
        evenement=formation, libelle='Restauration',
        type='depense', montant=Decimal('20000'),
        date=date.today() - timedelta(days=13), enregistre_par=admin
    )

    # Participations formation
    for email in ['oumar.ba@mouhtacimina.sn',
                  'fatou.sow@mouhtacimina.sn',
                  'aminata.fall@mouhtacimina.sn']:
        try:
            m = User.objects.get(email=email)
            Participation.objects.get_or_create(
                membre=m, evenement=formation,
                defaults={'statut': 'present'}
            )
        except User.DoesNotExist:
            pass

# Participations Gamou
for email in ['oumar.ba@mouhtacimina.sn',
              'fatou.sow@mouhtacimina.sn',
              'ibrahima.ndiaye@mouhtacimina.sn',
              'moussa.gueye@mouhtacimina.sn']:
    try:
        m = User.objects.get(email=email)
        Participation.objects.get_or_create(
            membre=m, evenement=gamou,
            defaults={'statut': 'inscrit'}
        )
    except User.DoesNotExist:
        pass

print("  ✓ Participations créées")

# ── Cotisations ───────────────────────────────────────────────
from cotisations.models import Cotisation, Paiement, CotisationMensuelleConfig

# Config mensuelle
config = CotisationMensuelleConfig.get()
print(f"\n  ✓ Config mensuelle : {config.montant_mensuel} FCFA")

# Cotisation mensuelle Avril 2026
cot_mensuelle, created = Cotisation.objects.get_or_create(
    titre='Cotisation Mensuelle — Avril 2026',
    defaults={
        'type_cotisation':  'mensuelle',
        'montant_suggere':  Decimal('1000'),
        'periodicite':      'mensuelle',
        'mois_concerne':    date(2026, 4, 1),
        'est_active':       True,
        'cree_par':         admin,
    }
)
print(f"\n  {'✓ Créée' if created else '~ Existe'} : Cotisation mensuelle Avril 2026")

# Cotisation Gamou
cot_gamou, created = Cotisation.objects.get_or_create(
    titre='Cotisation Gamou 2026',
    defaults={
        'type_cotisation':             'evenement',
        'montant_suggere':             Decimal('5000'),
        'reduction_membres_officiels': Decimal('1000'),
        'periodicite':                 'unique',
        'est_active':                  True,
        'description':                 'Participation aux frais du Gamou annuel 2026. '
                                       'Réduction de 1000 FCFA pour les membres officiels.',
        'cree_par':                    admin,
    }
)
print(f"  {'✓ Créée' if created else '~ Existe'} : Cotisation Gamou 2026")

# Paiements de test
paiements_data = [
    # Mensuelle — validés
    {
        'cotisation': cot_mensuelle,
        'email':      'oumar.ba@mouhtacimina.sn',
        'montant':    Decimal('1000'),
        'moyen':      'wave',
        'statut':     'valide',
        'ref':        'WV-2026041001',
    },
    {
        'cotisation': cot_mensuelle,
        'email':      'fatou.sow@mouhtacimina.sn',
        'montant':    Decimal('1000'),
        'moyen':      'orange_money',
        'statut':     'valide',
        'ref':        'OM-2026041002',
    },
    # Mensuelle — en attente
    {
        'cotisation': cot_mensuelle,
        'email':      'ibrahima.ndiaye@mouhtacimina.sn',
        'montant':    Decimal('1000'),
        'moyen':      'wave',
        'statut':     'en_attente',
        'ref':        'WV-2026041003',
    },
    # Gamou — membre officiel avec réduction
    {
        'cotisation': cot_gamou,
        'email':      'oumar.ba@mouhtacimina.sn',
        'montant':    Decimal('4000'),  # 5000 - 1000 réduction
        'moyen':      'wave',
        'statut':     'valide',
        'ref':        'WV-GAMOU-001',
    },
    # Gamou — sympathisant sans réduction
    {
        'cotisation': cot_gamou,
        'email':      'aminata.fall@mouhtacimina.sn',
        'montant':    Decimal('5000'),
        'moyen':      'especes',
        'statut':     'en_attente',
        'ref':        '',
    },
    # Gamou — en attente
    {
        'cotisation': cot_gamou,
        'email':      'moussa.gueye@mouhtacimina.sn',
        'montant':    Decimal('4000'),
        'moyen':      'free_money',
        'statut':     'en_attente',
        'ref':        'FM-GAMOU-003',
    },
]

for p_data in paiements_data:
    try:
        membre = User.objects.get(email=p_data['email'])
        p, created = Paiement.objects.get_or_create(
            cotisation=p_data['cotisation'],
            membre=membre,
            defaults={
                'montant':               p_data['montant'],
                'moyen':                 p_data['moyen'],
                'statut':                p_data['statut'],
                'reference_transaction': p_data['ref'],
                'valide_par':            admin if p_data['statut'] == 'valide' else None,
            }
        )
        if created:
            print(f"  ✓ Paiement : {membre.get_full_name()} — "
                  f"{p_data['montant']} FCFA ({p_data['statut']})")
    except User.DoesNotExist:
        print(f"  ✗ Membre non trouvé : {p_data['email']}")

print("\n✅ Données de test créées avec succès !\n")
print("═══════════════════════════════════════════")
print("  COMPTES DE TEST :")
print("═══════════════════════════════════════════")
print("  Super Admin  : admin@mouhtacimina.sn / admin1234")
print("  Admin Dakar  : admin.dakar@mouhtacimina.sn / admin1234")
print("  Membre UGB   : oumar.ba@mouhtacimina.sn / membre1234")
print("  Membre UGB   : fatou.sow@mouhtacimina.sn / membre1234")
print("  Sympathisant : aminata.fall@mouhtacimina.sn / membre1234")
print("═══════════════════════════════════════════\n")
PYSHELL

ok "Données de test créées"

# ─── 7. TESTER L'API ─────────────────────────────────────────
log "Test rapide de l'API..."

python3 manage.py shell << 'PYSHELL'
import json
from django.test import Client

c = Client()

# Test login
resp = c.post('/api/auth/login/',
    data=json.dumps({
        'email':    'admin@mouhtacimina.sn',
        'password': 'admin1234'
    }),
    content_type='application/json'
)

if resp.status_code == 200:
    data = resp.json()
    print(f"✅ Login OK — Token reçu pour : {data['membre']['nom_complet']}")
    print(f"   Rôle : {data['membre']['role_display']}")
    print(f"   Type : {data['membre']['type_membre_display']}")
else:
    print(f"❌ Login échoué : {resp.status_code}")
    print(resp.content.decode())
PYSHELL

# ─── 8. LANCER LE SERVEUR ────────────────────────────────────
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Backend prêt ! Lance le serveur :                 ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Terminal 1 — Django :${NC}"
echo "  python manage.py runserver 0.0.0.0:8000"
echo ""
echo -e "  ${BLUE}Terminal 2 — Flutter :${NC}"
echo "  cd .../mouhtacimina && flutter run"
echo ""
echo -e "  ${BLUE}Swagger UI :${NC}"
echo "  http://127.0.0.1:8000/api/docs/"
echo ""
echo -e "  ${YELLOW}COMPTES DE TEST :${NC}"
echo "  Super Admin  : admin@mouhtacimina.sn     / admin1234"
echo "  Admin Dakar  : admin.dakar@mouhtacimina.sn / admin1234"
echo "  Membre UGB   : oumar.ba@mouhtacimina.sn  / membre1234"
echo "  Sympathisant : aminata.fall@mouhtacimina.sn / membre1234"
echo ""

# Demander si lancer maintenant
read -p "Lancer le serveur Django maintenant ? (o/n) " rep
if [[ "$rep" == "o" || "$rep" == "O" ]]; then
    log "Lancement du serveur Django sur 0.0.0.0:8000..."
    python3 manage.py runserver 0.0.0.0:8000
fi
