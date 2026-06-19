from django.contrib import admin
from .models import Cotisation, Paiement, CotisationMensuelleConfig


class PaiementInline(admin.TabularInline):
    model          = Paiement
    extra          = 0
    readonly_fields = ['date_paiement', 'reduction_appliquee']
    fields         = [
        'membre', 'montant', 'moyen', 'statut',
        'reference_transaction', 'reduction_appliquee',
        'date_paiement', 'valide_par'
    ]


@admin.register(CotisationMensuelleConfig)
class ConfigAdmin(admin.ModelAdmin):
    list_display = ['montant_mensuel', 'jour_rappel', 'date_modification']


@admin.register(Cotisation)
class CotisationAdmin(admin.ModelAdmin):
    list_display  = [
        'titre', 'type_cotisation', 'cellule',
        'montant_suggere', 'reduction_membres_officiels',
        'est_active', 'total_collecte', 'nb_en_attente'
    ]
    list_filter   = ['type_cotisation', 'est_active', 'cellule']
    inlines       = [PaiementInline]


@admin.register(Paiement)
class PaiementAdmin(admin.ModelAdmin):
    list_display  = [
        'membre', 'cotisation', 'montant',
        'reduction_appliquee', 'moyen', 'statut', 'date_paiement'
    ]
    list_filter   = ['statut', 'moyen', 'cotisation__type_cotisation']
    search_fields = ['membre__email', 'reference_transaction']
    readonly_fields = ['date_paiement', 'reduction_appliquee']

    actions = ['valider_paiements', 'rejeter_paiements']

    def valider_paiements(self, request, queryset):
        from django.utils import timezone
        queryset.filter(statut='en_attente').update(
            statut='valide',
            valide_par=request.user,
            date_validation=timezone.now()
        )
    valider_paiements.short_description = "✓ Valider les paiements sélectionnés"

    def rejeter_paiements(self, request, queryset):
        queryset.filter(statut='en_attente').update(statut='rejete')
    rejeter_paiements.short_description = "✗ Rejeter les paiements sélectionnés"
