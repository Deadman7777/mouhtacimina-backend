from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, Cellule


@admin.register(Cellule)
class CelluleAdmin(admin.ModelAdmin):
    list_display = ['nom', 'date_creation']


@admin.register(User)
class MembreAdmin(UserAdmin):
    list_display  = [
        'email', 'nom_complet', 'type_membre', 'role',
        'cellule', 'est_bureau', 'poste_bureau',
        'est_actif', 'est_diplome'
    ]
    list_filter   = [
        'type_membre', 'role', 'cellule',
        'est_bureau', 'est_actif', 'est_diplome', 'ufr'
    ]
    search_fields = ['email', 'first_name', 'last_name', 'username']
    ordering      = ['last_name', 'first_name']

    fieldsets = UserAdmin.fieldsets + (
        ('Dahira — Rôle & Cellule', {
            'fields': (
                'role', 'type_membre', 'cellule',
                'telephone', 'photo', 'date_naissance',
                'adresse', 'statut_matrimonial', 'est_actif',
                'date_officialisation', 'date_signature_engagement',
            )
        }),
        ('Bureau', {
            'fields': ('est_bureau', 'poste_bureau'),
            'classes': ('collapse',),
        }),
        ('Académique', {
            'fields': (
                'ufr', 'specialite', 'niveau_etude',
                'promo', 'est_diplome', 'annee_diplome'
            ),
            'classes': ('collapse',),
        }),
    )
