from django.contrib import admin
from .models import Evenement, Participation, LigneBudget


class LigneBudgetInline(admin.TabularInline):
    model = LigneBudget
    extra = 0


class ParticipationInline(admin.TabularInline):
    model = Participation
    extra = 0


@admin.register(Evenement)
class EvenementAdmin(admin.ModelAdmin):
    list_display  = ['titre', 'type', 'statut', 'cellule', 'est_global', 'date_debut']
    list_filter   = ['statut', 'type', 'est_global', 'cellule']
    search_fields = ['titre']
    inlines       = [LigneBudgetInline, ParticipationInline]
