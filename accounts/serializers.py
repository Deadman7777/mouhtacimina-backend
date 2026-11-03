from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import User, Cellule


class CelluleSerializer(serializers.ModelSerializer):
    nom_display     = serializers.CharField(source='get_nom_display', read_only=True)
    bareme_display  = serializers.CharField(source='get_type_bareme_display', read_only=True)
    nb_membres      = serializers.SerializerMethodField()

    class Meta:
        model  = Cellule
        fields = ['id', 'nom', 'nom_display', 'description', 'date_creation',
                  'nb_membres', 'type_bareme', 'bareme_display', 'montant_cotisation']

    def get_nb_membres(self, obj):
        return obj.membres.filter(est_actif=True).count()


class MembreListSerializer(serializers.ModelSerializer):
    cellule_nom          = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    role_display         = serializers.CharField(source='get_role_display', read_only=True)
    type_membre_display  = serializers.CharField(source='get_type_membre_display', read_only=True)
    poste_bureau_display = serializers.CharField(source='get_poste_bureau_display', read_only=True)
    # Exposée dans la liste pour le compteur « en retard de cotisation » des
    # écrans admin (web et mobile) : sans elle, ce compteur restait à 0.
    dette_cotisation     = serializers.DecimalField(
        max_digits=10, decimal_places=2, read_only=True
    )

    class Meta:
        model  = User
        fields = [
            'id', 'first_name', 'last_name', 'email',
            'telephone', 'photo',
            'role', 'role_display',
            'type_membre', 'type_membre_display',
            'cellule', 'cellule_nom',
            'est_bureau', 'poste_bureau', 'poste_bureau_display',
            'est_actif', 'est_diplome', 'date_adhesion',
            'dette_cotisation',
        ]


class MembreDetailSerializer(serializers.ModelSerializer):
    cellule_nom          = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    role_display         = serializers.CharField(source='get_role_display', read_only=True)
    type_membre_display  = serializers.CharField(source='get_type_membre_display', read_only=True)
    ufr_display          = serializers.CharField(source='get_ufr_display', read_only=True)
    poste_bureau_display = serializers.CharField(source='get_poste_bureau_display', read_only=True)
    nom_complet          = serializers.CharField(read_only=True)
    dette_cotisation     = serializers.DecimalField(
        max_digits=10, decimal_places=2, read_only=True
    )
    objectif_cotisation_label = serializers.CharField(read_only=True)

    class Meta:
        model  = User
        fields = [
            'id', 'username', 'first_name', 'last_name', 'nom_complet',
            'email', 'telephone', 'photo', 'date_naissance', 'adresse',
            'statut_matrimonial',
            # Rôle & cellule
            'role', 'role_display', 'cellule', 'cellule_nom',
            'date_adhesion', 'est_actif',
            # Type membre
            'type_membre', 'type_membre_display',
            'date_officialisation', 'date_signature_engagement',
            'dette_cotisation', 'objectif_cotisation_label',
            # Bureau
            'est_bureau', 'poste_bureau', 'poste_bureau_display',
            # Académique
            'ufr', 'ufr_display', 'specialite', 'niveau_etude',
            'promo', 'est_diplome', 'annee_diplome',
        ]
        read_only_fields = ['date_adhesion', 'email', 'dette_cotisation']

    def validate_promo(self, value):
        # Même normalisation qu'à l'inscription : sans elle, une promo saisie
        # depuis l'édition de profil restait « 30 » au lieu de « P30 ».
        if value and not value.startswith('P'):
            value = f'P{value}'
        return value


class MonProfilSerializer(MembreDetailSerializer):
    """
    Édition de son propre profil (PATCH /api/auth/membres/moi/).

    Verrouille tout ce qui relève d'une décision du bureau. Sans ces
    read_only, n'importe quel membre pouvait s'attribuer role='super_admin',
    type_membre='officiel' ou changer de cellule par un simple PATCH.
    Les champs personnels envoyés par l'app mobile (nom, téléphone, adresse,
    statut matrimonial, infos académiques) restent modifiables.
    """

    class Meta(MembreDetailSerializer.Meta):
        read_only_fields = MembreDetailSerializer.Meta.read_only_fields + [
            'role', 'cellule', 'type_membre', 'est_actif',
            'est_bureau', 'poste_bureau',
            'date_officialisation', 'date_signature_engagement',
        ]


class AdminMembreSerializer(MembreDetailSerializer):
    """
    Modification du statut d'un membre par un admin (PATCH /membres/{id}/).

    Seuls le rôle, le type de membre (avec ses dates) et le poste au bureau
    sont modifiables ici. La cellule passe par `migrer_cellule` (qui gère
    les dettes), l'activation par `activer`, le reste par le membre lui-même.
    """
    CHAMPS_MODIFIABLES = [
        'role', 'type_membre', 'date_officialisation',
        'date_signature_engagement', 'est_bureau', 'poste_bureau',
    ]

    class Meta(MembreDetailSerializer.Meta):
        read_only_fields = [
            f for f in MembreDetailSerializer.Meta.fields
            if f not in [
                'role', 'type_membre', 'date_officialisation',
                'date_signature_engagement', 'est_bureau', 'poste_bureau',
            ]
        ]

    def validate(self, data):
        from django.utils import timezone
        request = self.context['request']
        membre  = self.instance

        nouveau_role = data.get('role', membre.role)
        if nouveau_role != membre.role:
            # Nommer ou retirer un admin est réservé au super admin, et
            # personne ne modifie son propre rôle (ni promotion, ni
            # rétrogradation accidentelle du seul super admin).
            if request.user.role != User.Role.SUPER_ADMIN:
                raise serializers.ValidationError(
                    {'role': "Seul le super admin peut modifier un rôle."})
            if membre.pk == request.user.pk:
                raise serializers.ValidationError(
                    {'role': "Vous ne pouvez pas modifier votre propre rôle."})

        est_bureau = data.get('est_bureau', membre.est_bureau)
        poste      = data.get('poste_bureau', membre.poste_bureau)
        if est_bureau and not poste:
            raise serializers.ValidationError(
                {'poste_bureau': "Choisissez le poste au bureau."})
        if not est_bureau:
            data['poste_bureau'] = ''

        # Passage officiel : la dette se calcule depuis la signature de
        # l'engagement. Sans date, elle resterait à 0 indéfiniment.
        type_membre = data.get('type_membre', membre.type_membre)
        if type_membre == User.TypeMembre.OFFICIEL:
            aujourd_hui = timezone.now().date()
            if not data.get('date_signature_engagement', membre.date_signature_engagement):
                data['date_signature_engagement'] = aujourd_hui
            if not data.get('date_officialisation', membre.date_officialisation):
                data['date_officialisation'] = aujourd_hui
        return data


class InscriptionSerializer(serializers.ModelSerializer):
    password  = serializers.CharField(write_only=True, min_length=8)
    password2 = serializers.CharField(write_only=True, label="Confirmation mot de passe")

    class Meta:
        model  = User
        fields = [
            'username', 'first_name', 'last_name', 'email',
            'telephone', 'password', 'password2',
            'cellule', 'type_membre',
            'ufr', 'specialite', 'niveau_etude', 'promo',
        ]

    def validate(self, data):
        if data['password'] != data.pop('password2'):
            raise serializers.ValidationError(
                {"password2": "Les mots de passe ne correspondent pas."}
            )
        return data
    
    def validate_promo(self, value):
        if value and not value.startswith('P'):
            value = f'P{value}'  # Ajouter P automatiquement
        return value

    def create(self, validated_data):
        password = validated_data.pop('password')
        # Nouveau membre = toujours role membre, admin assigne le type
        user = User(**validated_data)
        user.set_password(password)
        user.role = User.Role.MEMBRE
        user.save()
        return user


class ChangerMotDePasseSerializer(serializers.Serializer):
    ancien_mdp   = serializers.CharField(write_only=True)
    nouveau_mdp  = serializers.CharField(write_only=True, min_length=8)
    confirmation = serializers.CharField(write_only=True)

    def validate(self, data):
        if data['nouveau_mdp'] != data['confirmation']:
            raise serializers.ValidationError(
                {"confirmation": "Les mots de passe ne correspondent pas."}
            )
        return data


class TokenAvecInfosSerializer(TokenObtainPairSerializer):
    """JWT enrichi avec les infos du membre."""
    def validate(self, attrs):
        data         = super().validate(attrs)
        data['membre'] = MembreDetailSerializer(self.user).data
        return data
