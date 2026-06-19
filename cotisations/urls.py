from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    CotisationViewSet, PaiementAdminViewSet,
    initier_paiement_paytech, paytech_ipn,
)

router = DefaultRouter()
router.register('', CotisationViewSet, basename='cotisation')

admin_router = DefaultRouter()
admin_router.register('paiements', PaiementAdminViewSet, basename='admin-paiement')

urlpatterns = [
    path('admin/', include(admin_router.urls)),
    path('<int:cotisation_id>/payer-paytech/', initier_paiement_paytech,
         name='payer-paytech'),
    path('', include(router.urls)),
]
