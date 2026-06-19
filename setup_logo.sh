#!/bin/bash

# ============================================================
#   MOUHTACIMINA — Intégration du logo dans Flutter
#   Lance depuis le dossier PARENT du projet Flutter
#   (le même dossier d'où tu as lancé setup_flutter.sh)
#   Usage: ./setup_logo.sh
# ============================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

APP_NAME="mouhtacimina"
LOGO_SRC="mouhtacimina.jpeg"  # Le logo doit être dans le même dossier que ce script

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   MOUHTACIMINA — Intégration logo                   ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

# Vérifications
[ -f "$LOGO_SRC" ] || error "Logo '$LOGO_SRC' introuvable ! Place le fichier mouhtacimina.jpeg à côté de ce script."
[ -d "$APP_NAME" ] || error "Dossier '$APP_NAME' introuvable ! Lance setup_flutter.sh d'abord."

cd $APP_NAME

# ─── 1. COPIER LE LOGO ───────────────────────────────────────
log "Copie du logo dans assets/images/..."
mkdir -p assets/images
cp "../$LOGO_SRC" assets/images/logo.jpeg
ok "Logo copié → assets/images/logo.jpeg"

# ─── 2. VÉRIFIER PUBSPEC ─────────────────────────────────────
if ! grep -q "assets/images/" pubspec.yaml; then
  warn "assets/images/ absent du pubspec.yaml — ajout automatique..."
  sed -i 's/flutter:/flutter:\n  assets:\n    - assets\/images\//' pubspec.yaml
fi
ok "pubspec.yaml OK"

# ─── 3. APP LOGO WIDGET ──────────────────────────────────────
log "Création du widget AppLogo réutilisable..."

cat > lib/widgets/app_logo.dart << 'DART'
import 'package:flutter/material.dart';

/// Logo Mouhtacimina réutilisable partout dans l'app.
/// Usage :
///   AppLogo()                    → taille normale (120px)
///   AppLogo(size: 80)            → petite taille
///   AppLogo(size: 200, withText: true) → logo + nom + devise
class AppLogo extends StatelessWidget {
  final double size;
  final bool   withText;
  final bool   withDevise;

  const AppLogo({
    super.key,
    this.size      = 120,
    this.withText  = false,
    this.withDevise = false,
  });

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F6E56).withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.jpeg',
          fit: BoxFit.cover,
        ),
      ),
    );

    if (!withText) return logo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 16),
        const Text(
          'Mouhtacimina',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F6E56),
            letterSpacing: 0.5,
          ),
        ),
        if (withDevise) ...[
          const SizedBox(height: 4),
          const Text(
            'Foi · Discipline · Discrétion',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFFBA7517),
              fontStyle: FontStyle.italic,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Dahira Tidiane — UGB',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF5F5E5A),
            ),
          ),
        ],
      ],
    );
  }
}
DART
ok "widgets/app_logo.dart créé"

# ─── 4. LOGIN SCREEN AVEC VRAI LOGO ──────────────────────────
log "Mise à jour du login screen avec le logo..."

cat > lib/screens/auth/login_screen.dart << 'DART'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _mdpCtrl   = TextEditingController();
  bool  _mdpCache  = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _mdpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok   = await auth.login(_emailCtrl.text.trim(), _mdpCtrl.text);
    if (!mounted) return;
    if (ok) {
      context.go(auth.isAdmin ? '/admin' : '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Erreur de connexion'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(children: [

                // ── Logo + nom + devise ──────────────────────
                const AppLogo(size: 130, withText: true, withDevise: true),
                const SizedBox(height: 48),

                // ── Carte formulaire ─────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(children: [

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'ton@email.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) =>
                        (v?.contains('@') ?? false) ? null : 'Email invalide',
                    ),
                    const SizedBox(height: 16),

                    // Mot de passe
                    TextFormField(
                      controller: _mdpCtrl,
                      obscureText: _mdpCache,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_mdpCache
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _mdpCache = !_mdpCache),
                        ),
                      ),
                      validator: (v) =>
                        (v?.length ?? 0) >= 6 ? null : 'Mot de passe trop court',
                    ),
                    const SizedBox(height: 28),

                    // Bouton connexion
                    ElevatedButton(
                      onPressed: auth.isLoading ? null : _submit,
                      child: auth.isLoading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Se connecter',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // Inscription
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Pas encore membre ?",
                    style: TextStyle(color: AppTheme.textSecondary)),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text(
                      "S'inscrire",
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
DART
ok "login_screen.dart mis à jour avec le logo"

# ─── 5. SPLASH SCREEN ────────────────────────────────────────
log "Création de la splash screen..."

cat > lib/screens/splash_screen.dart << 'DART'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_logo.dart';

/// Splash screen affiché au démarrage pendant l'init de l'auth.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween(begin: 0.8, end: 1.0)
               .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    // Attendre l'animation + init auth
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    // Attendre que l'auth soit initialisée
    while (auth.status == AuthStatus.initial) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    if (auth.isLoggedIn) {
      context.go(auth.isAdmin ? '/admin' : '/home');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo blanc sur fond vert
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFBA7517), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/images/logo.jpeg', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Mouhtacimina',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Foi · Discipline · Discrétion',
                  style: TextStyle(
                    color: Color(0xFFBA7517),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 60),
                const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
DART
ok "screens/splash_screen.dart créé"

# ─── 6. METTRE À JOUR ROUTER POUR SPLASH ─────────────────────
log "Mise à jour du router pour inclure la splash screen..."

cat > lib/config/router.dart << 'DART'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/membre/home_screen.dart';
import '../screens/membre/profile_screen.dart';
import '../screens/membre/edit_profile_screen.dart';
import '../screens/membre/membres_screen.dart';
import '../screens/membre/evenements_screen.dart';
import '../screens/membre/evenement_detail_screen.dart';
import '../screens/membre/cotisations_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/gestion_membres_screen.dart';
import '../screens/admin/creer_evenement_screen.dart';
import '../screens/admin/valider_paiements_screen.dart';
import '../screens/admin/bilan_evenement_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AuthProvider auth) => GoRouter(
  navigatorKey:    _rootKey,
  initialLocation: '/splash',
  refreshListenable: auth,
  redirect: (context, state) {
    final loggedIn = auth.isLoggedIn;
    final loc      = state.matchedLocation;
    final isPublic = loc == '/splash' || loc == '/login' || loc == '/register';

    if (!loggedIn && !isPublic) return '/login';
    if (loggedIn && (loc == '/login' || loc == '/register')) {
      return auth.isAdmin ? '/admin' : '/home';
    }
    return null;
  },
  routes: [
    // Splash
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),

    // Auth
    GoRoute(path: '/login',    builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

    // Membre
    GoRoute(path: '/home',     builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/profil',   builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/profil/modifier', builder: (_, __) => const EditProfileScreen()),
    GoRoute(path: '/membres',  builder: (_, __) => const MembresScreen()),
    GoRoute(path: '/evenements', builder: (_, __) => const EvenementsScreen()),
    GoRoute(
      path: '/evenements/:id',
      builder: (_, state) => EvenementDetailScreen(
        evenementId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(path: '/cotisations', builder: (_, __) => const CotisationsScreen()),

    // Admin
    GoRoute(path: '/admin',    builder: (_, __) => const AdminDashboardScreen()),
    GoRoute(path: '/admin/membres',          builder: (_, __) => const GestionMembresScreen()),
    GoRoute(path: '/admin/evenements/creer', builder: (_, __) => const CreerEvenementScreen()),
    GoRoute(
      path: '/admin/paiements',
      builder: (_, state) => ValiderPaiementsScreen(
        cotisationId: int.tryParse(state.uri.queryParameters['cotisation'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/admin/evenements/:id/bilan',
      builder: (_, state) => BilanEvenementScreen(
        evenementId: int.parse(state.pathParameters['id']!),
      ),
    ),
  ],
);
DART
ok "router.dart mis à jour avec splash"

# ─── 7. APPBAR AVEC LOGO ─────────────────────────────────────
log "Création d'une AppBar custom avec logo..."

cat > lib/widgets/app_bar_logo.dart << 'DART'
import 'package:flutter/material.dart';
import '../config/theme.dart';

/// AppBar avec le logo Mouhtacimina à gauche.
/// Utilise-la en remplacement de AppBar() dans tes screens.
class MouhtaciminaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String  title;
  final List<Widget>? actions;
  final bool    showLogo;

  const MouhtaciminaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showLogo = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: showLogo
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.jpeg',
                fit: BoxFit.cover,
              ),
            ),
          )
        : null,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: Container(
          height: 2,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [
              Color(0xFFBA7517), // Doré
              Color(0xFF0F6E56), // Vert
            ]),
          ),
        ),
      ),
    );
  }
}
DART
ok "widgets/app_bar_logo.dart créé"

# ─── 8. FLUTTER PUB GET ──────────────────────────────────────
log "flutter pub get..."
flutter pub get
ok "Packages à jour"

# ─── FIN ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Logo intégré partout !                            ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Fichiers créés / modifiés :${NC}"
echo "  assets/images/logo.jpeg          → logo original"
echo "  lib/widgets/app_logo.dart        → widget logo réutilisable"
echo "  lib/widgets/app_bar_logo.dart    → AppBar avec logo + barre dorée"
echo "  lib/screens/splash_screen.dart   → splash animée (vert + doré)"
echo "  lib/screens/auth/login_screen.dart → logo dans le login"
echo "  lib/config/router.dart           → splash comme écran initial"
echo ""
echo -e "  ${YELLOW}Utilisation dans tes screens :${NC}"
echo ""
echo "  // Logo seul"
echo "  AppLogo(size: 120)"
echo ""
echo "  // Logo + nom + devise (login, onboarding)"
echo "  AppLogo(size: 130, withText: true, withDevise: true)"
echo ""
echo "  // AppBar avec logo (dans tous tes screens)"
echo "  appBar: MouhtaciminaAppBar(title: 'Membres')"
echo "  appBar: MouhtaciminaAppBar(title: 'Profil', actions: [IconButton(...)])"
echo ""
echo -e "  ${GREEN}Lance l'app :${NC} flutter run"
echo ""
