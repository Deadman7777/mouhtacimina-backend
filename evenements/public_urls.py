from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .public_views import EvenementPublicViewSet, stats_publiques

router = DefaultRouter()
router.register('evenements', EvenementPublicViewSet, basename='public-evenement')

urlpatterns = [
    path('stats/', stats_publiques, name='public-stats'),
    path('', include(router.urls)),
]
