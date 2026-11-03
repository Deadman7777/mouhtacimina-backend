"""
Serializers publics — consommés par des visiteurs NON authentifiés.

Règle : aucune donnée financière interne ici (ni budget_prevu, ni budget_reel,
ni lignes_budget, ni total_collecte). Ne jamais réutiliser dans une vue
publique les serializers de evenements/serializers.py, qui exposent le budget
aux admins. Seul le montant de participation demandé au public est exposé.
"""
from django.utils import timezone
from rest_framework import serializers

from .models import Evenement


class ParticipationPubliqueSerializer(serializers.Serializer):
    """
    Campagne de cotisation rattachée à l'événement : ce que le visiteur
    devra payer s'il veut participer. Lecture seule.
    """
    id              = serializers.IntegerField()
    titre           = serializers.CharField()
    montant_suggere = serializers.DecimalField(max_digits=10, decimal_places=2)
    date_limite     = serializers.DateField()


class EvenementPublicMixin:
    """Champs calculés partagés entre la liste et le détail."""

    def get_portee(self, obj):
        if obj.est_global:
            return 'Tout le dahira'
        return obj.cellule.get_nom_display() if obj.cellule else 'Tout le dahira'

    def _fin(self, obj):
        return obj.date_fin or obj.date_debut

    def get_est_passe(self, obj):
        return self._fin(obj) < timezone.now()

    def get_inscriptions_ouvertes(self, obj):
        return (obj.statut == Evenement.Statut.LANCE
                and not self.get_est_passe(obj))


class EvenementPublicListSerializer(EvenementPublicMixin,
                                    serializers.ModelSerializer):
    type_display          = serializers.CharField(source='get_type_display', read_only=True)
    portee                = serializers.SerializerMethodField()
    resume                = serializers.SerializerMethodField()
    est_passe             = serializers.SerializerMethodField()
    inscriptions_ouvertes = serializers.SerializerMethodField()

    class Meta:
        model  = Evenement
        fields = [
            'id', 'titre', 'resume', 'type', 'type_display',
            'lieu', 'date_debut', 'date_fin',
            'est_global', 'portee',
            'est_passe', 'inscriptions_ouvertes',
        ]

    def get_resume(self, obj):
        texte = (obj.description or '').strip()
        if len(texte) <= 180:
            return texte
        return texte[:180].rsplit(' ', 1)[0] + '…'


class EvenementPublicDetailSerializer(EvenementPublicMixin,
                                      serializers.ModelSerializer):
    type_display          = serializers.CharField(source='get_type_display', read_only=True)
    portee                = serializers.SerializerMethodField()
    est_passe             = serializers.SerializerMethodField()
    inscriptions_ouvertes = serializers.SerializerMethodField()
    participation         = serializers.SerializerMethodField()

    class Meta:
        model  = Evenement
        fields = [
            'id', 'titre', 'description', 'type', 'type_display',
            'lieu', 'date_debut', 'date_fin',
            'est_global', 'portee',
            'est_passe', 'inscriptions_ouvertes', 'participation',
        ]

    def get_participation(self, obj):
        """Campagne active rattachée à l'événement, s'il y en a une."""
        cotisation = obj.cotisations.filter(est_active=True).first()
        if cotisation is None:
            return None
        return ParticipationPubliqueSerializer(cotisation).data
