from rest_framework.permissions import BasePermission


class IsSuperAdmin(BasePermission):
    """Seul le super admin peut accéder."""
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'super_admin'


class IsAdminCellule(BasePermission):
    """Admin cellule, super admin ou membre du bureau."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        return request.user.role in [
            'super_admin', 'admin_cellule'
        ] or request.user.est_bureau


class IsAdminOrReadOnly(BasePermission):
    """Lecture pour tous les membres, écriture pour les admins."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        if request.method in ('GET', 'HEAD', 'OPTIONS'):
            return True
        return request.user.role in ['super_admin', 'admin_cellule']


class IsMembresMemeCellule(BasePermission):
    """Un membre ne peut voir que les membres de sa cellule (sauf admin)."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        if request.user.role in ['super_admin', 'admin_cellule']:
            return True
        return True  # filtrage fait dans le queryset

    def has_object_permission(self, request, view, obj):
        if request.user.role in ['super_admin', 'admin_cellule']:
            return True
        return obj.cellule == request.user.cellule
