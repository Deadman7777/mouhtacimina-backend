from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from decimal import Decimal
from datetime import date, timedelta
import os

from accounts.models import Cellule

User = get_user_model()


class Command(BaseCommand):
    help = "Initialise les données de base (cellules + super admin) en production"

    def handle(self, *args, **options):
        self.stdout.write("Initialisation des données Mouhtacimina...\n")

        # ── 1. Cellules avec barèmes ─────────────────────────
        config = {
            'UGB':      ('Cellule mère — Saint-Louis', 'mensuel', Decimal('1000')),
            'DAKAR':    ('Cellule Dakar — anciens',     'annuel',  Decimal('50000')),
            'NORD':     ('Cellule Nord — anciens',      'annuel',  Decimal('50000')),
            'DIASPORA': ('Cellule Diaspora',            'aucun',   Decimal('0')),
        }

        for nom, (desc, bareme, montant) in config.items():
            c, created = Cellule.objects.get_or_create(
                nom=nom,
                defaults={
                    'description': desc,
                    'type_bareme': bareme,
                    'montant_cotisation': montant,
                }
            )
            if not created:
                c.type_bareme        = bareme
                c.montant_cotisation = montant
                c.save()
            etat = "créée" if created else "mise à jour"
            self.stdout.write(
                f"  Cellule {c.get_nom_display()} {etat} "
                f"({bareme}, {montant} FCFA)"
            )

        # ── 2. Super admin (depuis variables d'environnement) ─
        admin_email = os.environ.get('ADMIN_EMAIL')
        admin_pass  = os.environ.get('ADMIN_PASSWORD')

        if admin_email and admin_pass:
            ugb = Cellule.objects.filter(nom='UGB').first()
            admin, created = User.objects.get_or_create(
                email=admin_email,
                defaults={
                    'username':     admin_email.split('@')[0],
                    'first_name':   'Mouhtacimina',
                    'last_name':    'Admin',
                    'role':         'super_admin',
                    'type_membre':  'officiel',
                    'cellule':      ugb,
                    'est_bureau':   True,
                    'poste_bureau': 'president',
                    'date_signature_engagement': date.today() - timedelta(days=1),
                    'is_staff':     True,
                    'is_superuser': True,
                }
            )
            if created:
                admin.set_password(admin_pass)
                admin.save()
                self.stdout.write(
                    self.style.SUCCESS(f"  Super admin créé : {admin_email}")
                )
            else:
                self.stdout.write(f"  Super admin existe déjà : {admin_email}")
        else:
            self.stdout.write(
                self.style.WARNING(
                    "  ADMIN_EMAIL / ADMIN_PASSWORD non définis — "
                    "super admin non créé"
                )
            )

        self.stdout.write(self.style.SUCCESS("\nInitialisation terminée."))
