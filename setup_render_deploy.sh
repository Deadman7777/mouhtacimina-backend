#!/bin/bash

# ============================================================
#   MOUHTACIMINA — Préparation déploiement Render
#   Lance depuis la racine du projet Django (où est manage.py)
# ============================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   MOUHTACIMINA — Préparation Render                 ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

[ -f "manage.py" ] || { echo "Lance depuis la racine du projet Django"; exit 1; }

# Activer virtualenv
if [ -z "$VIRTUAL_ENV" ]; then
    for venv in env venv .venv; do
        [ -d "$venv" ] && source "$venv/bin/activate" && break
    done
fi

# ─── 1. INSTALLER LES DÉPENDANCES MANQUANTES ─────────────────
log "Installation gunicorn + dépendances prod..."
pip install gunicorn python-dateutil requests --quiet
ok "Dépendances installées"

# ─── 2. GÉNÉRER requirements.txt À JOUR ──────────────────────
log "Mise à jour de requirements.txt..."
pip freeze > requirements.txt
ok "requirements.txt régénéré ($(wc -l < requirements.txt) paquets)"

# ─── 3. BUILD SCRIPT POUR RENDER ─────────────────────────────
log "Création de build.sh (script de build Render)..."

cat > build.sh << 'BUILDSH'
#!/usr/bin/env bash
# Script de build exécuté par Render à chaque déploiement
set -o errexit

pip install -r requirements.txt

python manage.py collectstatic --no-input
python manage.py migrate
BUILDSH
chmod +x build.sh
ok "build.sh créé"

# ─── 4. SAUVEGARDE settings.py ───────────────────────────────
SETTINGS="mouhtacimina/settings.py"
cp "$SETTINGS" "${SETTINGS}.bak"
log "Sauvegarde settings.py → settings.py.bak"

# ─── 5. ADAPTER settings.py POUR LA PROD ─────────────────────
log "Adaptation de settings.py pour Render (compatible dev local)..."

python3 - << 'PYFIX'
with open('mouhtacimina/settings.py', 'r') as f:
    content = f.read()

# 5.1 — Importer os et dj_database_url en haut si absent
if 'import dj_database_url' not in content:
    content = content.replace(
        'from pathlib import Path',
        'from pathlib import Path\nimport os\nimport dj_database_url'
    )

# 5.2 — SECRET_KEY depuis l'environnement (fallback dev)
import re
content = re.sub(
    r"SECRET_KEY = '[^']*'",
    "SECRET_KEY = os.environ.get('SECRET_KEY', 'django-insecure-dev-key-change-me')",
    content
)

# 5.3 — DEBUG depuis l'environnement
content = re.sub(
    r"DEBUG = True",
    "DEBUG = os.environ.get('DEBUG', 'True') == 'True'",
    content,
    count=1
)

# 5.4 — ALLOWED_HOSTS : ajouter le domaine Render
content = re.sub(
    r"ALLOWED_HOSTS = \[[^\]]*\]",
    "ALLOWED_HOSTS = ['*']  # Render fournit le domaine ; '*' OK pour démarrer",
    content
)

# 5.5 — DATABASES : utiliser DATABASE_URL si présent (Render), sinon local
old_db_start = content.find("DATABASES = {")
old_db_end   = content.find("}", content.find("}", old_db_start) + 1) + 1
# On remplace tout le bloc DATABASES par une version hybride
nouveau_db = '''DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'mouhtacimina',
        'USER': 'postgres',
        'PASSWORD': 'SangueBiDiop@7',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}

# En production (Render), DATABASE_URL est défini → on l'utilise
if os.environ.get('DATABASE_URL'):
    DATABASES['default'] = dj_database_url.config(
        default=os.environ.get('DATABASE_URL'),
        conn_max_age=600,
        ssl_require=True,
    )'''

# Trouver le bloc DATABASES complet (jusqu'à l'accolade fermante de premier niveau)
import re
db_pattern = re.compile(r"DATABASES = \{.*?\n\}", re.DOTALL)
content = db_pattern.sub(nouveau_db, content, count=1)

# 5.6 — WhiteNoise pour les fichiers statiques
if 'whitenoise.middleware.WhiteNoiseMiddleware' not in content:
    content = content.replace(
        "'django.middleware.security.SecurityMiddleware',",
        "'django.middleware.security.SecurityMiddleware',\n    'whitenoise.middleware.WhiteNoiseMiddleware',"
    )

# 5.7 — STATIC_ROOT + storage WhiteNoise
if 'STATIC_ROOT' not in content:
    content = content.replace(
        "STATIC_URL = 'static/'",
        """STATIC_URL = 'static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
STORAGES = {
    'default': {
        'BACKEND': 'django.core.files.storage.FileSystemStorage',
    },
    'staticfiles': {
        'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage',
    },
}"""
    )

# 5.8 — Paytech : lire les clés depuis l'environnement (avec fallback actuel)
content = re.sub(
    r"PAYTECH_API_KEY    = '[^']*'",
    "PAYTECH_API_KEY    = os.environ.get('PAYTECH_API_KEY', '')",
    content
)
content = re.sub(
    r"PAYTECH_API_SECRET = '[^']*'",
    "PAYTECH_API_SECRET = os.environ.get('PAYTECH_API_SECRET', '')",
    content
)

# 5.9 — IPN URL depuis l'environnement (l'URL Render en prod)
content = re.sub(
    r"PAYTECH_IPN_URL    = '[^']*'",
    "PAYTECH_IPN_URL    = os.environ.get('PAYTECH_IPN_URL', 'http://localhost:8000/api/payment/ipn/')",
    content
)

with open('mouhtacimina/settings.py', 'w') as f:
    f.write(content)
print("✅ settings.py adapté pour Render (et compatible dev local)")
PYFIX
ok "settings.py adapté"

# ─── 6. FICHIER .gitignore ───────────────────────────────────
log "Mise à jour .gitignore..."
cat > .gitignore << 'GITIGNORE'
# Python
__pycache__/
*.py[cod]
*.egg-info/
.Python

# Django
*.log
db.sqlite3
/media
/staticfiles

# Environnement
.env
env/
venv/
.venv/

# Sauvegardes
*.bak

# IDE
.vscode/
.idea/
GITIGNORE
ok ".gitignore créé"

# ─── 7. PROCFILE (optionnel mais propre) ─────────────────────
log "Création du Procfile..."
echo "web: gunicorn mouhtacimina.wsgi:application" > Procfile
ok "Procfile créé"

# ─── 8. VÉRIFICATION ─────────────────────────────────────────
log "Vérification Django (dev local doit toujours marcher)..."
python3 manage.py check
ok "Django OK"

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Préparation Render — Done !                       ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Fichiers créés :${NC}"
echo "  ✓ build.sh           — script de build Render"
echo "  ✓ Procfile           — commande de démarrage gunicorn"
echo "  ✓ .gitignore         — exclut .env, env/, *.bak"
echo "  ✓ requirements.txt   — régénéré avec gunicorn + dateutil + requests"
echo "  ✓ settings.py        — lit DATABASE_URL, SECRET_KEY, clés Paytech"
echo "                         depuis l'environnement (dev local intact)"
echo ""
echo -e "  ${YELLOW}IMPORTANT — Variables d'env à définir sur Render :${NC}"
echo "  SECRET_KEY          → une longue chaîne aléatoire"
echo "  DEBUG               → False"
echo "  DATABASE_URL        → fourni automatiquement par Render"
echo "  PAYTECH_API_KEY     → ta clé Paytech"
echo "  PAYTECH_API_SECRET  → ta clé secrète Paytech"
echo "  PAYTECH_IPN_URL     → https://TON-APP.onrender.com/api/payment/ipn/"
echo ""
echo -e "  ${BLUE}Prochaine étape :${NC} pousser sur GitHub puis créer le service Render"
echo ""
