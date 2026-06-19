from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework import status

from .views import LoginView, MembreViewSet, CelluleViewSet
from .serializers import InscriptionSerializer, MembreDetailSerializer

router = DefaultRouter()
router.register('membres',  MembreViewSet,  basename='membre')
router.register('cellules', CelluleViewSet, basename='cellule')

@api_view(['POST'])
@permission_classes([AllowAny])
def inscrire(request):
    serializer = InscriptionSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    membre = serializer.save(role='membre')

    # Générer les tokens JWT comme pour le login
    refresh = RefreshToken.for_user(membre)
    return Response({
        'access':  str(refresh.access_token),
        'refresh': str(refresh),
        'membre':  MembreDetailSerializer(membre).data,
    }, status=status.HTTP_201_CREATED)

urlpatterns = [
    path('login/',    LoginView.as_view(),       name='login'),
    path('refresh/',  TokenRefreshView.as_view(), name='token_refresh'),
    path('inscrire/', inscrire,                   name='inscrire'),
    path('',          include(router.urls)),
]
