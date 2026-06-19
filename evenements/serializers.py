from rest_framework import serializers
from .models import Evenement, Participation, LigneBudget
from accounts.serializers import MembreListSerializer


class LigneBudgetSerializer(serializers.ModelSerializer):
    enregistre_par_nom = serializers.CharField(
        source='enregistre_par.nom_complet', read_only=True
    )

    class Meta:
        model  = LigneBudget
        fields = [
            'id', 'libelle', 'type', 'montant', 'date',
            'note', 'enregistre_par', 'enregistre_par_nom',
        ]
        read_only_fields = ['enregistre_par']

    def create(self, validated_data):
        validated_data['enregistre_par'] = self.context['request'].user
        return super().create(validated_data)


class ParticipationSerializer(serializers.ModelSerializer):
    membre_info = MembreListSerializer(source='membre', read_only=True)

    class Meta:
        model  = Participation
        fields = ['id', 'membre', 'membre_info', 'evenement', 'statut', 'date_inscription', 'note']
        read_only_fields = ['date_inscription']


class EvenementListSerializer(serializers.ModelSerializer):
    cellule_nom      = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    type_display     = serializers.CharField(source='get_type_display', read_only=True)
    statut_display   = serializers.CharField(source='get_statut_display', read_only=True)
    nb_participants  = serializers.IntegerField(read_only=True)

    class Meta:
        model  = Evenement
        fields = [
            'id', 'titre', 'type', 'type_display',
            'statut', 'statut_display', 'est_global',
            'cellule', 'cellule_nom', 'lieu',
            'date_debut', 'date_fin', 'budget_prevu',
            'nb_participants',
        ]


class EvenementDetailSerializer(serializers.ModelSerializer):
    cellule_nom    = serializers.CharField(source='cellule.get_nom_display', read_only=True)
    type_display   = serializers.CharField(source='get_type_display', read_only=True)
    statut_display = serializers.CharField(source='get_statut_display', read_only=True)
    cree_par_nom   = serializers.CharField(source='cree_par.nom_complet', read_only=True)
    lignes_budget  = LigneBudgetSerializer(many=True, read_only=True)
    nb_participants = serializers.IntegerField(read_only=True)
    budget_reel    = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model  = Evenement
        fields = [
            'id', 'titre', 'description', 'type', 'type_display',
            'statut', 'statut_display', 'est_global',
            'cellule', 'cellule_nom', 'lieu',
            'date_debut', 'date_fin', 'budget_prevu', 'budget_reel',
            'nb_participants', 'lignes_budget',
            'cree_par', 'cree_par_nom',
            'date_creation', 'date_modification',
        ]
        read_only_fields = ['cree_par', 'date_creation', 'date_modification', 'statut']

    def create(self, validated_data):
        validated_data['cree_par'] = self.context['request'].user
        return super().create(validated_data)


class BilanSerializer(serializers.Serializer):
    """Bilan complet d'un événement."""
    evenement_id   = serializers.IntegerField()
    titre          = serializers.CharField()
    statut         = serializers.CharField()
    nb_inscrits    = serializers.IntegerField()
    nb_presents    = serializers.IntegerField()
    nb_absents     = serializers.IntegerField()
    taux_presence  = serializers.FloatField()
    budget_prevu   = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_recettes = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_depenses = serializers.DecimalField(max_digits=12, decimal_places=2)
    solde          = serializers.DecimalField(max_digits=12, decimal_places=2)
    lignes_budget  = LigneBudgetSerializer(many=True)
