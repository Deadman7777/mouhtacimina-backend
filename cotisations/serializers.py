from rest_framework import serializers
from .models import Cotisation, Paiement, CotisationMensuelleConfig
from accounts.serializers import MembreListSerializer


class PaiementSerializer(serializers.ModelSerializer):
    membre_info         = MembreListSerializer(source='membre', read_only=True)
    moyen_display       = serializers.CharField(source='get_moyen_display', read_only=True)
    statut_display      = serializers.CharField(source='get_statut_display', read_only=True)
    valide_par_nom      = serializers.CharField(source='valide_par.nom_complet', read_only=True)

    class Meta:
        model  = Paiement
        fields = [
            'id', 'cotisation', 'membre', 'membre_info',
            'montant', 'moyen', 'moyen_display',
            'statut', 'statut_display',
            'reference_transaction', 'reduction_appliquee',
            'date_paiement', 'date_validation',
            'valide_par', 'valide_par_nom', 'note',
        ]
        read_only_fields = [
            'date_paiement', 'date_validation',
            'valide_par', 'statut', 'reduction_appliquee'
        ]

    def create(self, validated_data):
        validated_data['membre'] = self.context['request'].user
        return super().create(validated_data)


class ValiderPaiementSerializer(serializers.Serializer):
    statut = serializers.ChoiceField(choices=['valide', 'rejete'])
    note   = serializers.CharField(required=False, allow_blank=True)


class CotisationListSerializer(serializers.ModelSerializer):
    cellule_nom              = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    periodicite_display      = serializers.CharField(source='get_periodicite_display', read_only=True)
    type_cotisation_display  = serializers.CharField(source='get_type_cotisation_display', read_only=True)
    total_collecte           = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    nb_paiements             = serializers.IntegerField(source='nb_paiements_valides', read_only=True)
    nb_en_attente            = serializers.IntegerField(read_only=True)
    # Montant personnalisé selon le membre connecté
    montant_pour_moi         = serializers.SerializerMethodField()

    class Meta:
        model  = Cotisation
        fields = [
            'id', 'titre', 'type_cotisation', 'type_cotisation_display',
            'cellule', 'cellule_nom',
            'montant_suggere', 'reduction_membres_officiels', 'montant_pour_moi',
            'periodicite', 'periodicite_display',
            'date_limite', 'est_active', 'mois_concerne',
            'total_collecte', 'nb_paiements', 'nb_en_attente',
        ]

    def get_montant_pour_moi(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            montant = obj.montant_pour_membre(request.user)
            return str(montant) if montant is not None else None
        return None


class CotisationDetailSerializer(CotisationListSerializer):
    paiements    = PaiementSerializer(many=True, read_only=True)
    cree_par_nom = serializers.CharField(source='cree_par.nom_complet', read_only=True)

    class Meta(CotisationListSerializer.Meta):
        fields = CotisationListSerializer.Meta.fields + [
            'description', 'paiements', 'cree_par', 'cree_par_nom', 'date_creation',
        ]
        read_only_fields = ['cree_par', 'date_creation']

    def create(self, validated_data):
        validated_data['cree_par'] = self.context['request'].user
        return super().create(validated_data)


class ConfigMensuelleSerializer(serializers.ModelSerializer):
    class Meta:
        model  = CotisationMensuelleConfig
        fields = ['montant_mensuel', 'jour_rappel']
