#!/bin/bash

# ============================================================
#   MOUHTACIMINA — Barème par cellule + Migration de cellule
#   Lance depuis la racine du projet Django
#   (là où se trouve manage.py)
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
echo -e "${GREEN}   MOUHTACIMINA — Barème cellule + Migration         ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

[ -f "manage.py" ] || { echo "Lance depuis la racine du projet Django"; exit 1; }

# Activer virtualenv
if [ -z "$VIRTUAL_ENV" ]; then
    for venv in env venv .venv; do
        [ -d "$venv" ] && source "$venv/bin/activate" && break
    done
fi

# ═══════════════════════════════════════════════════════════════
# 1. MODÈLE CELLULE — ajouter le barème de cotisation
# ═══════════════════════════════════════════════════════════════

log "Mise à jour du modèle Cellule (barème de cotisation)..."

python3 - << 'PYFIX'
with open('accounts/models.py', 'r') as f:
    content = f.read()

# Remplacer la classe Cellule pour ajouter le barème
old_cellule = """class Cellule(models.Model):
    class Nom(models.TextChoices):
        UGB      = 'UGB',      'Cellule UGB (Mère)'
        DAKAR    = 'DAKAR',    'Cellule Dakar'
        NORD     = 'NORD',     'Cellule Nord'
        DIASPORA = 'DIASPORA', 'Cellule Diaspora'

    nom           = models.CharField(max_length=20, choices=Nom.choices, unique=True)
    description   = models.TextField(blank=True)
    date_creation = models.DateField(auto_now_add=True)

    class Meta:
        verbose_name = 'Cellule'
        ordering = ['nom']

    def __str__(self):
        return self.get_nom_display()"""

new_cellule = """class Cellule(models.Model):
    class Nom(models.TextChoices):
        UGB      = 'UGB',      'Cellule UGB (Mère)'
        DAKAR    = 'DAKAR',    'Cellule Dakar'
        NORD     = 'NORD',     'Cellule Nord'
        DIASPORA = 'DIASPORA', 'Cellule Diaspora'

    # Type de barème de cotisation appliqué aux membres de la cellule
    class TypeBareme(models.TextChoices):
        MENSUEL = 'mensuel', 'Mensuel (étudiants)'   # 1000 FCFA / mois
        ANNUEL  = 'annuel',  'Annuel (anciens)'      # 50000 FCFA / an
        AUCUN   = 'aucun',   'Aucun (en attente)'    # Diaspora pour l'instant

    nom           = models.CharField(max_length=20, choices=Nom.choices, unique=True)
    description   = models.TextField(blank=True)
    date_creation = models.DateField(auto_now_add=True)

    # ── Barème de cotisation de la cellule ───────────────────
    type_bareme = models.CharField(
        max_length=10,
        choices=TypeBareme.choices,
        default=TypeBareme.MENSUEL,
        help_text="Mensuel = 1000/mois (UGB), Annuel = 50000/an (Dakar, Nord)"
    )
    montant_cotisation = models.DecimalField(
        max_digits=10, decimal_places=2,
        default=1000,
        help_text="Montant de référence : 1000 (mensuel) ou 50000 (annuel)"
    )

    class Meta:
        verbose_name = 'Cellule'
        ordering = ['nom']

    def __str__(self):
        return self.get_nom_display()

    @property
    def est_annuel(self):
        return self.type_bareme == self.TypeBareme.ANNUEL

    @property
    def est_mensuel(self):
        return self.type_bareme == self.TypeBareme.MENSUEL"""

content = content.replace(old_cellule, new_cellule)

with open('accounts/models.py', 'w') as f:
    f.write(content)
print("✅ Modèle Cellule mis à jour (type_bareme + montant_cotisation)")
PYFIX
ok "Modèle Cellule mis à jour"

# ═══════════════════════════════════════════════════════════════
# 2. MODÈLE USER — nouvelle logique de dette + migration
# ═══════════════════════════════════════════════════════════════

log "Mise à jour de la property dette_cotisation + méthode migrer_cellule..."

python3 - << 'PYFIX'
with open('accounts/models.py', 'r') as f:
    content = f.read()

# Remplacer toute la property dette_cotisation
old_dette = '''    @property
    def dette_cotisation(self):
        """
        Calcule la dette accumulée du membre officiel.
        Dette = (mois non payés depuis signature) × 1000 FCFA
        """
        if not self.est_officiel or not self.date_signature_engagement:
            return 0

        from cotisations.models import Paiement
        from dateutil.relativedelta import relativedelta
        from decimal import Decimal

        MONTANT_MENSUEL = Decimal('1000')
        aujourd_hui     = timezone.now().date()
        debut           = self.date_signature_engagement

        # Nombre de mois depuis la signature
        diff        = relativedelta(aujourd_hui, debut)
        total_mois  = diff.years * 12 + diff.months + 1  # +1 pour le mois en cours

        # Total dû
        total_du = MONTANT_MENSUEL * total_mois

        # Total payé sur cotisations mensuelles validées
        total_paye = Paiement.objects.filter(
            membre=self,
            statut='valide',
            cotisation__type_cotisation='mensuelle'
        ).aggregate(
            t=models.Sum('montant')
        )['t'] or Decimal('0')

        dette = total_du - total_paye
        return max(dette, Decimal('0'))  # jamais négatif'''

new_dette = '''    @property
    def total_paye_mensuel(self):
        """Total des paiements validés sur cotisations mensuelles."""
        from cotisations.models import Paiement
        from decimal import Decimal
        return Paiement.objects.filter(
            membre=self,
            statut='valide',
            cotisation__type_cotisation='mensuelle'
        ).aggregate(t=models.Sum('montant'))['t'] or Decimal('0')

    @property
    def dette_cotisation(self):
        """
        Calcule la dette accumulée du membre officiel.
        Le barème dépend de la cellule :
          - Cellule mensuelle (UGB)  : 1000 FCFA × mois depuis signature
          - Cellule annuelle (Dakar, Nord) : 50000 FCFA × années depuis signature
          - Cellule sans barème (Diaspora) : 0
        """
        from dateutil.relativedelta import relativedelta
        from decimal import Decimal

        # Pas officiel, pas de signature, ou pas de cellule => pas de dette
        if not self.est_officiel or not self.date_signature_engagement:
            return Decimal('0')
        if not self.cellule:
            return Decimal('0')

        aujourd_hui = timezone.now().date()
        debut       = self.date_signature_engagement
        diff        = relativedelta(aujourd_hui, debut)

        bareme = self.cellule.type_bareme

        if bareme == Cellule.TypeBareme.ANNUEL:
            # Anciens : 50000 par année entamée depuis la signature
            montant_annuel = self.cellule.montant_cotisation  # 50000
            nb_annees      = diff.years + 1  # +1 pour l'année en cours
            total_du       = montant_annuel * nb_annees

        elif bareme == Cellule.TypeBareme.MENSUEL:
            # Étudiants : 1000 par mois entamé depuis la signature
            montant_mensuel = self.cellule.montant_cotisation  # 1000
            nb_mois         = diff.years * 12 + diff.months + 1  # +1 mois en cours
            total_du        = montant_mensuel * nb_mois

        else:
            # Aucun barème (Diaspora en attente)
            return Decimal('0')

        dette = total_du - self.total_paye_mensuel
        return max(dette, Decimal('0'))

    @property
    def objectif_cotisation_label(self):
        """Texte décrivant l'objectif de cotisation selon la cellule."""
        if not self.cellule:
            return ''
        bareme = self.cellule.type_bareme
        montant = self.cellule.montant_cotisation
        if bareme == Cellule.TypeBareme.ANNUEL:
            return f'{montant:.0f} FCFA / an'
        if bareme == Cellule.TypeBareme.MENSUEL:
            return f'{montant:.0f} FCFA / mois'
        return ''

    def migrer_cellule(self, nouvelle_cellule, admin=None):
        """
        Migre le membre vers une nouvelle cellule.
        Les dettes en cours sont effacées (les anciens paiements mensuels
        non validés sont annulés et l'engagement est réinitialisé à aujourd'hui),
        et le nouvel objectif de cotisation s'applique immédiatement.
        """
        from cotisations.models import Paiement

        ancienne = self.cellule

        # 1. Annuler les paiements mensuels en attente (dette en cours)
        Paiement.objects.filter(
            membre=self,
            statut='en_attente',
            cotisation__type_cotisation='mensuelle'
        ).update(
            statut='rejete',
            note='Annulé suite à migration de cellule'
        )

        # 2. Réinitialiser l'engagement à aujourd'hui
        #    => repart de zéro avec le nouveau barème, dette = 0
        self.cellule                   = nouvelle_cellule
        self.date_signature_engagement = timezone.now().date()
        self.save(update_fields=['cellule', 'date_signature_engagement'])

        return {
            'ancienne_cellule': ancienne.get_nom_display() if ancienne else None,
            'nouvelle_cellule': nouvelle_cellule.get_nom_display(),
            'nouvel_objectif':  self.objectif_cotisation_label,
        }'''

content = content.replace(old_dette, new_dette)

with open('accounts/models.py', 'w') as f:
    f.write(content)
print("✅ dette_cotisation adaptée + migrer_cellule ajoutée")
PYFIX
ok "Modèle User mis à jour"

# ═══════════════════════════════════════════════════════════════
# 3. ENDPOINT DE MIGRATION (admin)
# ═══════════════════════════════════════════════════════════════

log "Ajout de l'endpoint de migration dans accounts/views.py..."

python3 - << 'PYFIX'
with open('accounts/views.py', 'r') as f:
    content = f.read()

# Vérifier les imports nécessaires
if 'from rest_framework.decorators import action' not in content:
    # Ajouter l'import action s'il manque
    content = content.replace(
        'from rest_framework import viewsets',
        'from rest_framework import viewsets\nfrom rest_framework.decorators import action'
    )

# Ajouter l'action migrer dans MembreViewSet
# On cherche la fin de la méthode get_permissions pour insérer après
marker = """        # Détail / modification : authentifié (son propre profil)
        return [IsAuthenticated()]"""

migration_action = """        # Détail / modification : authentifié (son propre profil)
        return [IsAuthenticated()]

    @action(detail=True, methods=['post'], permission_classes=[IsAdminCellule])
    def migrer_cellule(self, request, pk=None):
        \"\"\"
        POST /api/auth/membres/{id}/migrer_cellule/
        Body: { "cellule": <id_nouvelle_cellule> }
        Migre un membre vers une nouvelle cellule.
        Les dettes en cours sont effacées, le nouveau barème s'applique.
        \"\"\"
        from .models import Cellule
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
            'membre':  MembreDetailSerializer(membre, context={'request': request}).data,
        })"""

content = content.replace(marker, migration_action)

# S'assurer que status et Response sont importés
if 'from rest_framework.response import Response' not in content:
    content = content.replace(
        'from rest_framework import viewsets',
        'from rest_framework import viewsets, status\nfrom rest_framework.response import Response'
    )
if 'from rest_framework import viewsets, status' not in content and 'import status' not in content:
    content = content.replace(
        'from rest_framework import viewsets',
        'from rest_framework import viewsets, status'
    )

with open('accounts/views.py', 'w') as f:
    f.write(content)
print("✅ Endpoint migrer_cellule ajouté")
PYFIX
ok "Endpoint migration ajouté"

# ═══════════════════════════════════════════════════════════════
# 4. SERIALIZER — exposer le barème et l'objectif
# ═══════════════════════════════════════════════════════════════

log "Mise à jour des serializers (barème cellule + objectif)..."

python3 - << 'PYFIX'
with open('accounts/serializers.py', 'r') as f:
    content = f.read()

# Ajouter les champs au CelluleSerializer s'ils n'y sont pas
if 'type_bareme' not in content:
    # Chercher le CelluleSerializer
    if "fields = ['id', 'nom'" in content:
        # Ajouter type_bareme et montant_cotisation aux fields cellule
        import re
        # On ajoute après 'nom' dans les fields du CelluleSerializer
        content = content.replace(
            "class CelluleSerializer",
            "class CelluleSerializer"
        )
    print("⚠️  Vérifie manuellement CelluleSerializer pour ajouter type_bareme")

# Ajouter objectif_cotisation_label au MembreDetailSerializer
if 'objectif_cotisation_label' not in content:
    print("⚠️  Pense à ajouter 'objectif_cotisation_label' au MembreDetailSerializer si besoin")

with open('accounts/serializers.py', 'w') as f:
    f.write(content)
print("✅ Serializers vérifiés")
PYFIX

# Afficher le serializer pour vérification manuelle
echo ""
warn "Affichage du CelluleSerializer et MembreDetailSerializer pour vérification :"
echo ""
grep -n "class CelluleSerializer" -A 10 accounts/serializers.py || true
echo "..."
grep -n "class MembreDetailSerializer" -A 5 accounts/serializers.py || true

# ═══════════════════════════════════════════════════════════════
# 5. MIGRATIONS
# ═══════════════════════════════════════════════════════════════

echo ""
log "Création des migrations..."
python3 manage.py makemigrations accounts
ok "Migrations créées"

log "Application des migrations..."
python3 manage.py migrate
ok "Migrations appliquées"

# ═══════════════════════════════════════════════════════════════
# 6. CONFIGURER LES BARÈMES DES CELLULES
# ═══════════════════════════════════════════════════════════════

log "Configuration des barèmes par cellule..."

python3 manage.py shell << 'PYSHELL'
from accounts.models import Cellule
from decimal import Decimal

config = {
    'UGB':      ('mensuel', Decimal('1000')),
    'DAKAR':    ('annuel',  Decimal('50000')),
    'NORD':     ('annuel',  Decimal('50000')),
    'DIASPORA': ('aucun',   Decimal('0')),
}

for nom, (bareme, montant) in config.items():
    try:
        c = Cellule.objects.get(nom=nom)
        c.type_bareme        = bareme
        c.montant_cotisation = montant
        c.save()
        print(f"  ✓ {c.get_nom_display()} : {bareme} — {montant} FCFA")
    except Cellule.DoesNotExist:
        print(f"  ⚠️  Cellule {nom} introuvable")

print("\n✅ Barèmes configurés")
PYSHELL
ok "Barèmes configurés"

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Barème + Migration Django — Done !                ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Ce qui a changé :${NC}"
echo "  ✓ Cellule : type_bareme (mensuel/annuel/aucun) + montant_cotisation"
echo "  ✓ Barèmes configurés :"
echo "      UGB      → 1 000 FCFA / mois"
echo "      Dakar    → 50 000 FCFA / an"
echo "      Nord     → 50 000 FCFA / an"
echo "      Diaspora → aucun (en attente)"
echo "  ✓ dette_cotisation : calcul adapté selon la cellule"
echo "  ✓ Endpoint : POST /api/auth/membres/{id}/migrer_cellule/"
echo "      → change la cellule + efface les dettes + nouveau barème"
echo ""
echo -e "  ${YELLOW}Vérifie le CelluleSerializer ci-dessus${NC} pour exposer"
echo "  type_bareme et montant_cotisation au frontend si besoin."
echo ""
echo -e "  ${GREEN}Prochaine étape : écran de migration côté Flutter${NC}"
echo ""
