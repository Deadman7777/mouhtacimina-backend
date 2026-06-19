from django.contrib import admin
from cotisations.views import paytech_ipn
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path('admin/', admin.site.urls),

    # Auth & membres
    path('api/auth/',        include('accounts.urls')),

    # Événements
    path('api/evenements/',  include('evenements.urls')),

    # Cotisations
    path('api/cotisations/', include('cotisations.urls')),
    path('api/payment/ipn/', paytech_ipn, name='paytech-ipn'),

    # Docs Swagger
    path('api/schema/',  SpectacularAPIView.as_view(),          name='schema'),
    path('api/docs/',    SpectacularSwaggerView.as_view(
                           url_name='schema'), name='swagger-ui'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
