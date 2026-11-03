"""
Droits sur la fiche des membres : ajout, statut (rôle, type, bureau),
activation, migration. Lancer : python manage.py test accounts
"""
from rest_framework.test import APITestCase

from .models import Cellule, User


class DroitsMembresTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.ugb, _ = Cellule.objects.get_or_create(nom='UGB')
        cls.dakar, _ = Cellule.objects.get_or_create(nom='DAKAR')

        def creer(email, **champs):
            u = User(username=email, email=email, first_name=email.split('@')[0], **champs)
            u.set_password('motdepasse-test')
            u.save()
            return u

        cls.super_admin = creer('super@test.sn', role='super_admin', cellule=cls.ugb)
        cls.admin_ugb = creer('admin.ugb@test.sn', role='admin_cellule', cellule=cls.ugb)
        cls.bureau_ugb = creer('bureau@test.sn', role='membre', cellule=cls.ugb,
                               est_bureau=True, poste_bureau='sg')
        cls.membre_ugb = creer('membre@test.sn', role='membre', cellule=cls.ugb)

    def url(self, membre, suffixe=''):
        return f'/api/auth/membres/{membre.id}/{suffixe}'

    # ── Rôle ────────────────────────────────────────────────────
    def test_super_admin_nomme_un_admin_cellule(self):
        self.client.force_authenticate(self.super_admin)
        r = self.client.patch(self.url(self.membre_ugb), {'role': 'admin_cellule'})
        self.assertEqual(r.status_code, 200, r.data)
        self.membre_ugb.refresh_from_db()
        self.assertEqual(self.membre_ugb.role, 'admin_cellule')

    def test_admin_cellule_ne_peut_pas_changer_un_role(self):
        self.client.force_authenticate(self.admin_ugb)
        r = self.client.patch(self.url(self.membre_ugb), {'role': 'super_admin'})
        self.assertEqual(r.status_code, 400)
        self.membre_ugb.refresh_from_db()
        self.assertEqual(self.membre_ugb.role, 'membre')

    def test_bureau_ne_peut_rien_modifier(self):
        """Faille d'origine : un membre du bureau pouvait se promouvoir super admin."""
        self.client.force_authenticate(self.bureau_ugb)
        r = self.client.patch(self.url(self.bureau_ugb), {'role': 'super_admin'})
        self.assertEqual(r.status_code, 403)
        r = self.client.patch(self.url(self.membre_ugb), {'type_membre': 'officiel'})
        self.assertEqual(r.status_code, 403)

    def test_personne_ne_change_son_propre_role(self):
        self.client.force_authenticate(self.super_admin)
        r = self.client.patch(self.url(self.super_admin), {'role': 'membre'})
        self.assertEqual(r.status_code, 400)

    # ── Type et bureau ──────────────────────────────────────────
    def test_passage_officiel_date_l_engagement(self):
        self.client.force_authenticate(self.admin_ugb)
        r = self.client.patch(self.url(self.membre_ugb), {'type_membre': 'officiel'})
        self.assertEqual(r.status_code, 200, r.data)
        self.membre_ugb.refresh_from_db()
        self.assertEqual(self.membre_ugb.type_membre, 'officiel')
        self.assertIsNotNone(self.membre_ugb.date_signature_engagement)
        self.assertIsNotNone(self.membre_ugb.date_officialisation)

    def test_bureau_exige_un_poste_et_le_retrait_l_efface(self):
        self.client.force_authenticate(self.admin_ugb)
        r = self.client.patch(self.url(self.membre_ugb), {'est_bureau': True})
        self.assertEqual(r.status_code, 400)
        r = self.client.patch(self.url(self.bureau_ugb), {'est_bureau': False})
        self.assertEqual(r.status_code, 200, r.data)
        self.bureau_ugb.refresh_from_db()
        self.assertEqual(self.bureau_ugb.poste_bureau, '')

    def test_cellule_et_email_non_modifiables_par_patch(self):
        self.client.force_authenticate(self.super_admin)
        self.client.patch(self.url(self.membre_ugb),
                          {'cellule': self.dakar.id, 'email': 'pirate@test.sn'})
        self.membre_ugb.refresh_from_db()
        self.assertEqual(self.membre_ugb.cellule, self.ugb)
        self.assertEqual(self.membre_ugb.email, 'membre@test.sn')

    # ── Ajout ───────────────────────────────────────────────────
    def donnees_ajout(self, **extra):
        return {
            'username': 'nouveau@test.sn', 'email': 'nouveau@test.sn',
            'first_name': 'Nouveau', 'last_name': 'Membre',
            'password': 'provisoire-123', 'password2': 'provisoire-123',
            'cellule': self.dakar.id, 'type_membre': 'sympathisant', **extra,
        }

    def test_admin_cellule_ajoute_dans_sa_cellule_seulement(self):
        self.client.force_authenticate(self.admin_ugb)
        r = self.client.post('/api/auth/membres/', self.donnees_ajout())
        self.assertEqual(r.status_code, 201, r.data)
        self.assertIn('id', r.data)
        nouveau = User.objects.get(email='nouveau@test.sn')
        self.assertEqual(nouveau.cellule, self.ugb)
        self.assertEqual(nouveau.role, 'membre')
        self.assertTrue(nouveau.check_password('provisoire-123'))

    def test_super_admin_choisit_la_cellule(self):
        self.client.force_authenticate(self.super_admin)
        r = self.client.post('/api/auth/membres/', self.donnees_ajout(role='super_admin'))
        self.assertEqual(r.status_code, 201, r.data)
        nouveau = User.objects.get(email='nouveau@test.sn')
        self.assertEqual(nouveau.cellule, self.dakar)
        self.assertEqual(nouveau.role, 'membre')  # jamais admin à la création

    def test_ajout_officiel_date_l_engagement(self):
        self.client.force_authenticate(self.super_admin)
        r = self.client.post('/api/auth/membres/', self.donnees_ajout(type_membre='officiel'))
        self.assertEqual(r.status_code, 201, r.data)
        self.assertIsNotNone(User.objects.get(email='nouveau@test.sn').date_signature_engagement)

    def test_simple_membre_ne_peut_pas_desactiver(self):
        self.client.force_authenticate(self.membre_ugb)
        self.assertEqual(self.client.post(self.url(self.bureau_ugb, 'activer/')).status_code, 403)

    def test_bureau_ne_peut_pas_ajouter(self):
        self.client.force_authenticate(self.bureau_ugb)
        r = self.client.post('/api/auth/membres/', self.donnees_ajout())
        self.assertEqual(r.status_code, 403)

    # ── Activation / migration ──────────────────────────────────
    def test_bureau_ne_peut_ni_desactiver_ni_migrer(self):
        self.client.force_authenticate(self.bureau_ugb)
        self.assertEqual(self.client.post(self.url(self.membre_ugb, 'activer/')).status_code, 403)
        r = self.client.post(self.url(self.membre_ugb, 'migrer_cellule/'), {'cellule': self.dakar.id})
        self.assertEqual(r.status_code, 403)

    def test_bureau_garde_la_lecture_de_l_annuaire(self):
        self.client.force_authenticate(self.bureau_ugb)
        self.assertEqual(self.client.get('/api/auth/membres/').status_code, 200)
