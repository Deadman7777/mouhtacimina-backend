#!/bin/bash

# ============================================================
#   MOUHTACIMINA APP — Setup Flutter complet
#   Lance depuis le dossier parent où créer le projet Flutter
#   Usage: ./setup_flutter.sh
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

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   MOUHTACIMINA — Setup Flutter complet              ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

command -v flutter &>/dev/null || error "Flutter non trouvé. Installe Flutter d'abord : https://flutter.dev"

# ─── CRÉER LE PROJET ─────────────────────────────────────────
if [ ! -d "$APP_NAME" ]; then
  log "Création du projet Flutter '$APP_NAME'..."
  flutter create --org com.mouhtacimina --platforms android,ios $APP_NAME
  ok "Projet Flutter créé"
else
  warn "Dossier '$APP_NAME' existe déjà, on continue"
fi

cd $APP_NAME

# ─── PUBSPEC ─────────────────────────────────────────────────
log "Écriture du pubspec.yaml..."
cat > pubspec.yaml << 'YAML'
name: mouhtacimina
description: Application de gestion du Dahira Mouhtacimina
publish_to: none
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # HTTP & API
  dio: ^5.4.0
  pretty_dio_logger: ^1.3.1

  # State management
  provider: ^6.1.2

  # Navigation
  go_router: ^13.2.0

  # Stockage sécurisé (JWT)
  flutter_secure_storage: ^9.0.0

  # UI
  cached_network_image: ^3.3.1
  flutter_svg: ^2.0.9
  shimmer: ^3.0.0

  # Formulaires & validation
  image_picker: ^1.0.7

  # Dates & formats
  intl: ^0.19.0
  timeago: ^3.6.0

  cupertino_icons: ^1.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
YAML
ok "pubspec.yaml écrit"

# ─── STRUCTURE DOSSIERS ──────────────────────────────────────
log "Création de la structure des dossiers..."

mkdir -p lib/config
mkdir -p lib/models
mkdir -p lib/services
mkdir -p lib/providers
mkdir -p lib/screens/auth
mkdir -p lib/screens/membre
mkdir -p lib/screens/admin
mkdir -p lib/widgets
mkdir -p assets/images
mkdir -p assets/icons

ok "Dossiers créés"

# ═══════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════

# ── api_config.dart ──────────────────────────────────────────
cat > lib/config/api_config.dart << 'DART'
class ApiConfig {
  // Change en production
  static const String baseUrl = 'http://10.0.2.2:8000/api'; // Android emulator
  // static const String baseUrl = 'http://localhost:8000/api'; // iOS simulator
  // static const String baseUrl = 'https://ton-domaine.com/api'; // Production

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  // Endpoints Auth
  static const String login         = '/auth/login/';
  static const String refresh       = '/auth/refresh/';
  static const String inscrire      = '/auth/membres/inscrire/';
  static const String moi           = '/auth/membres/moi/';
  static const String changerMdp    = '/auth/membres/moi/changer-mdp/';
  static const String cellules      = '/auth/cellules/';
  static const String membres       = '/auth/membres/';

  // Endpoints Événements
  static const String evenements    = '/evenements/';

  // Endpoints Cotisations
  static const String cotisations   = '/cotisations/';
  static const String mesPaiements  = '/cotisations/mes-paiements/';
}
DART
ok "config/api_config.dart"

# ── theme.dart ───────────────────────────────────────────────
cat > lib/config/theme.dart << 'DART'
import 'package:flutter/material.dart';

class AppTheme {
  // Couleurs Mouhtacimina (vert Tidiane + doré)
  static const Color primary     = Color(0xFF0F6E56); // Vert Tidiane
  static const Color primaryLight = Color(0xFF1D9E75);
  static const Color accent      = Color(0xFFBA7517); // Doré
  static const Color danger      = Color(0xFFE24B4A);
  static const Color warning     = Color(0xFFEF9F27);
  static const Color success     = Color(0xFF639922);
  static const Color textPrimary = Color(0xFF2C2C2A);
  static const Color textSecondary = Color(0xFF5F5E5A);
  static const Color background  = Color(0xFFF1EFE8);
  static const Color surface     = Color(0xFFFFFFFF);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      surface: surface,
      background: background,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    ),
    fontFamily: 'SF Pro Display',
  );
}

// Extensions pratiques
extension ColorX on String {
  Color get roleColor {
    switch (this) {
      case 'super_admin':   return const Color(0xFF534AB7);
      case 'admin_cellule': return const Color(0xFF0F6E56);
      case 'membre_actif':  return const Color(0xFF185FA5);
      case 'membre_alumni': return const Color(0xFF854F0B);
      default:              return const Color(0xFF5F5E5A);
    }
  }

  Color get statutEvenementColor {
    switch (this) {
      case 'brouillon': return const Color(0xFF888780);
      case 'lance':     return const Color(0xFF1D9E75);
      case 'cloture':   return const Color(0xFF993C1D);
      default:          return const Color(0xFF888780);
    }
  }

  Color get statutPaiementColor {
    switch (this) {
      case 'en_attente': return const Color(0xFFBA7517);
      case 'valide':     return const Color(0xFF639922);
      case 'rejete':     return const Color(0xFFE24B4A);
      default:           return const Color(0xFF888780);
    }
  }
}
DART
ok "config/theme.dart"

# ── router.dart ──────────────────────────────────────────────
cat > lib/config/router.dart << 'DART'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
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
  navigatorKey: _rootKey,
  initialLocation: '/login',
  refreshListenable: auth,
  redirect: (context, state) {
    final loggedIn  = auth.isLoggedIn;
    final isAuth    = state.matchedLocation.startsWith('/login') ||
                      state.matchedLocation.startsWith('/register');

    if (!loggedIn && !isAuth) return '/login';
    if (loggedIn && isAuth) {
      // Rediriger selon le rôle
      return auth.isAdmin ? '/admin' : '/home';
    }
    return null;
  },
  routes: [
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
    GoRoute(path: '/admin/membres',   builder: (_, __) => const GestionMembresScreen()),
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
ok "config/router.dart"

# ═══════════════════════════════════════════════════════════════
# MODELS
# ═══════════════════════════════════════════════════════════════

cat > lib/models/cellule.dart << 'DART'
class Cellule {
  final int    id;
  final String nom;
  final String nomDisplay;
  final String description;
  final int    nbMembres;

  const Cellule({
    required this.id,
    required this.nom,
    required this.nomDisplay,
    required this.description,
    required this.nbMembres,
  });

  factory Cellule.fromJson(Map<String, dynamic> j) => Cellule(
    id:          j['id'],
    nom:         j['nom'],
    nomDisplay:  j['nom_display'] ?? j['nom'],
    description: j['description'] ?? '',
    nbMembres:   j['nb_membres']  ?? 0,
  );
}
DART
ok "models/cellule.dart"

cat > lib/models/membre.dart << 'DART'
import 'cellule.dart';

enum Role {
  superAdmin('super_admin', 'Super Admin'),
  adminCellule('admin_cellule', 'Admin Cellule'),
  membreActif('membre_actif', 'Membre Actif'),
  membreAlumni('membre_alumni', 'Membre Alumni');

  final String value;
  final String label;
  const Role(this.value, this.label);

  static Role fromString(String v) =>
    Role.values.firstWhere((r) => r.value == v, orElse: () => Role.membreActif);

  bool get isAdmin => this == Role.superAdmin || this == Role.adminCellule;
}

class Membre {
  final int     id;
  final String  username;
  final String  firstName;
  final String  lastName;
  final String  email;
  final String  telephone;
  final String? photo;
  final String  role;
  final String  roleDisplay;
  final int?    celluleId;
  final String? celluleNom;
  final bool    estActif;
  final bool    estDiplome;
  final String  dateAdhesion;
  // Académique
  final String  ufr;
  final String  ufrDisplay;
  final String  specialite;
  final String  niveauEtude;
  final String  promo;
  final String  anneeDiplome;
  // Perso
  final String  adresse;
  final String  statutMatrimonial;
  final String? dateNaissance;

  const Membre({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.telephone,
    this.photo,
    required this.role,
    required this.roleDisplay,
    this.celluleId,
    this.celluleNom,
    required this.estActif,
    required this.estDiplome,
    required this.dateAdhesion,
    required this.ufr,
    required this.ufrDisplay,
    required this.specialite,
    required this.niveauEtude,
    required this.promo,
    required this.anneeDiplome,
    required this.adresse,
    required this.statutMatrimonial,
    this.dateNaissance,
  });

  String get nomComplet => '$firstName $lastName'.trim();
  Role   get roleEnum   => Role.fromString(role);
  bool   get isAdmin    => roleEnum.isAdmin;

  factory Membre.fromJson(Map<String, dynamic> j) => Membre(
    id:               j['id'],
    username:         j['username']          ?? '',
    firstName:        j['first_name']        ?? '',
    lastName:         j['last_name']         ?? '',
    email:            j['email']             ?? '',
    telephone:        j['telephone']         ?? '',
    photo:            j['photo'],
    role:             j['role']              ?? 'membre_actif',
    roleDisplay:      j['role_display']      ?? '',
    celluleId:        j['cellule'],
    celluleNom:       j['cellule_nom'],
    estActif:         j['est_actif']         ?? true,
    estDiplome:       j['est_diplome']       ?? false,
    dateAdhesion:     j['date_adhesion']     ?? '',
    ufr:              j['ufr']               ?? '',
    ufrDisplay:       j['ufr_display']       ?? '',
    specialite:       j['specialite']        ?? '',
    niveauEtude:      j['niveau_etude']      ?? '',
    promo:            j['promo']             ?? '',
    anneeDiplome:     j['annee_diplome']     ?? '',
    adresse:          j['adresse']           ?? '',
    statutMatrimonial: j['statut_matrimonial'] ?? '',
    dateNaissance:    j['date_naissance'],
  );

  Map<String, dynamic> toJson() => {
    'first_name':         firstName,
    'last_name':          lastName,
    'telephone':          telephone,
    'adresse':            adresse,
    'statut_matrimonial': statutMatrimonial,
    'ufr':                ufr,
    'specialite':         specialite,
    'niveau_etude':       niveauEtude,
    'promo':              promo,
  };
}
DART
ok "models/membre.dart"

cat > lib/models/evenement.dart << 'DART'
class Evenement {
  final int     id;
  final String  titre;
  final String  description;
  final String  type;
  final String  typeDisplay;
  final String  statut;
  final String  statutDisplay;
  final bool    estGlobal;
  final int?    celluleId;
  final String? celluleNom;
  final String  lieu;
  final String  dateDebut;
  final String? dateFin;
  final double  budgetPrevu;
  final double? budgetReel;
  final int     nbParticipants;

  const Evenement({
    required this.id,
    required this.titre,
    required this.description,
    required this.type,
    required this.typeDisplay,
    required this.statut,
    required this.statutDisplay,
    required this.estGlobal,
    this.celluleId,
    this.celluleNom,
    required this.lieu,
    required this.dateDebut,
    this.dateFin,
    required this.budgetPrevu,
    this.budgetReel,
    required this.nbParticipants,
  });

  factory Evenement.fromJson(Map<String, dynamic> j) => Evenement(
    id:             j['id'],
    titre:          j['titre']          ?? '',
    description:    j['description']    ?? '',
    type:           j['type']           ?? '',
    typeDisplay:    j['type_display']   ?? '',
    statut:         j['statut']         ?? 'brouillon',
    statutDisplay:  j['statut_display'] ?? '',
    estGlobal:      j['est_global']     ?? false,
    celluleId:      j['cellule'],
    celluleNom:     j['cellule_nom'],
    lieu:           j['lieu']           ?? '',
    dateDebut:      j['date_debut']     ?? '',
    dateFin:        j['date_fin'],
    budgetPrevu:    double.tryParse(j['budget_prevu']?.toString() ?? '0') ?? 0,
    budgetReel:     double.tryParse(j['budget_reel']?.toString()  ?? '0'),
    nbParticipants: j['nb_participants'] ?? 0,
  );
}

class LigneBudget {
  final int    id;
  final String libelle;
  final String type; // recette | depense
  final double montant;
  final String date;
  final String note;

  const LigneBudget({
    required this.id,
    required this.libelle,
    required this.type,
    required this.montant,
    required this.date,
    required this.note,
  });

  factory LigneBudget.fromJson(Map<String, dynamic> j) => LigneBudget(
    id:      j['id'],
    libelle: j['libelle'] ?? '',
    type:    j['type']    ?? '',
    montant: double.tryParse(j['montant']?.toString() ?? '0') ?? 0,
    date:    j['date']    ?? '',
    note:    j['note']    ?? '',
  );
}

class BilanEvenement {
  final int    evenementId;
  final String titre;
  final String statut;
  final int    nbInscrits;
  final int    nbPresents;
  final int    nbAbsents;
  final double tauxPresence;
  final double budgetPrevu;
  final double totalRecettes;
  final double totalDepenses;
  final double solde;
  final List<LigneBudget> lignesBudget;

  const BilanEvenement({
    required this.evenementId,
    required this.titre,
    required this.statut,
    required this.nbInscrits,
    required this.nbPresents,
    required this.nbAbsents,
    required this.tauxPresence,
    required this.budgetPrevu,
    required this.totalRecettes,
    required this.totalDepenses,
    required this.solde,
    required this.lignesBudget,
  });

  factory BilanEvenement.fromJson(Map<String, dynamic> j) => BilanEvenement(
    evenementId:   j['evenement_id'],
    titre:         j['titre']          ?? '',
    statut:        j['statut']         ?? '',
    nbInscrits:    j['nb_inscrits']    ?? 0,
    nbPresents:    j['nb_presents']    ?? 0,
    nbAbsents:     j['nb_absents']     ?? 0,
    tauxPresence:  (j['taux_presence'] ?? 0).toDouble(),
    budgetPrevu:   double.tryParse(j['budget_prevu']?.toString()    ?? '0') ?? 0,
    totalRecettes: double.tryParse(j['total_recettes']?.toString()  ?? '0') ?? 0,
    totalDepenses: double.tryParse(j['total_depenses']?.toString()  ?? '0') ?? 0,
    solde:         double.tryParse(j['solde']?.toString()           ?? '0') ?? 0,
    lignesBudget:  (j['lignes_budget'] as List? ?? [])
                     .map((e) => LigneBudget.fromJson(e)).toList(),
  );
}
DART
ok "models/evenement.dart"

cat > lib/models/cotisation.dart << 'DART'
class Cotisation {
  final int     id;
  final String  titre;
  final String  description;
  final int?    celluleId;
  final String? celluleNom;
  final double? montantSuggere;
  final String  periodicite;
  final String  periodiciteDisplay;
  final String? dateLimite;
  final bool    estActive;
  final double  totalCollecte;
  final int     nbPaiements;

  const Cotisation({
    required this.id,
    required this.titre,
    required this.description,
    this.celluleId,
    this.celluleNom,
    this.montantSuggere,
    required this.periodicite,
    required this.periodiciteDisplay,
    this.dateLimite,
    required this.estActive,
    required this.totalCollecte,
    required this.nbPaiements,
  });

  factory Cotisation.fromJson(Map<String, dynamic> j) => Cotisation(
    id:                 j['id'],
    titre:              j['titre']               ?? '',
    description:        j['description']         ?? '',
    celluleId:          j['cellule'],
    celluleNom:         j['cellule_nom'],
    montantSuggere:     double.tryParse(j['montant_suggere']?.toString() ?? ''),
    periodicite:        j['periodicite']         ?? '',
    periodiciteDisplay: j['periodicite_display'] ?? '',
    dateLimite:         j['date_limite'],
    estActive:          j['est_active']          ?? true,
    totalCollecte:      double.tryParse(j['total_collecte']?.toString() ?? '0') ?? 0,
    nbPaiements:        j['nb_paiements']        ?? 0,
  );
}

class Paiement {
  final int     id;
  final int     cotisationId;
  final int     membreId;
  final String  membreNom;
  final double  montant;
  final String  moyen;
  final String  moyenDisplay;
  final String  statut;
  final String  statutDisplay;
  final String  referenceTransaction;
  final String  datePaiement;
  final String? dateValidation;
  final String  note;

  const Paiement({
    required this.id,
    required this.cotisationId,
    required this.membreId,
    required this.membreNom,
    required this.montant,
    required this.moyen,
    required this.moyenDisplay,
    required this.statut,
    required this.statutDisplay,
    required this.referenceTransaction,
    required this.datePaiement,
    this.dateValidation,
    required this.note,
  });

  factory Paiement.fromJson(Map<String, dynamic> j) {
    final membre = j['membre_info'] as Map<String, dynamic>?;
    return Paiement(
      id:                   j['id'],
      cotisationId:         j['cotisation'],
      membreId:             j['membre'],
      membreNom:            membre != null
                              ? '${membre['first_name']} ${membre['last_name']}'.trim()
                              : '',
      montant:              double.tryParse(j['montant']?.toString() ?? '0') ?? 0,
      moyen:                j['moyen']               ?? '',
      moyenDisplay:         j['moyen_display']       ?? '',
      statut:               j['statut']              ?? '',
      statutDisplay:        j['statut_display']      ?? '',
      referenceTransaction: j['reference_transaction'] ?? '',
      datePaiement:         j['date_paiement']       ?? '',
      dateValidation:       j['date_validation'],
      note:                 j['note']                ?? '',
    );
  }
}
DART
ok "models/cotisation.dart"

# ═══════════════════════════════════════════════════════════════
# SERVICES
# ═══════════════════════════════════════════════════════════════

cat > lib/services/storage_service.dart << 'DART'
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyAccess  = 'access_token';
  static const _keyRefresh = 'refresh_token';

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _keyAccess,  value: access);
    await _storage.write(key: _keyRefresh, value: refresh);
  }

  static Future<String?> getAccessToken()  => _storage.read(key: _keyAccess);
  static Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);

  static Future<void> clearAll() => _storage.deleteAll();
}
DART
ok "services/storage_service.dart"

cat > lib/services/api_client.dart << 'DART'
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/api_config.dart';
import 'storage_service.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() { _setup(); }

  late final Dio dio;

  void _setup() {
    dio = Dio(BaseOptions(
      baseUrl:        ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    // Logger (désactiver en production)
    dio.interceptors.add(PrettyDioLogger(
      requestHeader: false,
      requestBody: true,
      responseBody: true,
    ));

    // JWT interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await StorageService.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Tenter de rafraîchir le token
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Relancer la requête originale avec le nouveau token
            final token = await StorageService.getAccessToken();
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          }
        }
        handler.next(error);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refresh = await StorageService.getRefreshToken();
      if (refresh == null) return false;

      final res = await Dio().post(
        '${ApiConfig.baseUrl}${ApiConfig.refresh}',
        data: {'refresh': refresh},
      );
      await StorageService.saveTokens(
        access:  res.data['access'],
        refresh: refresh,
      );
      return true;
    } catch (_) {
      await StorageService.clearAll();
      return false;
    }
  }
}
DART
ok "services/api_client.dart"

cat > lib/services/auth_service.dart << 'DART'
import '../config/api_config.dart';
import '../models/membre.dart';
import 'api_client.dart';
import 'storage_service.dart';

class AuthService {
  final _dio = ApiClient().dio;

  Future<Membre> login(String email, String password) async {
    final res = await _dio.post(ApiConfig.login, data: {
      'email':    email,
      'password': password,
    });
    await StorageService.saveTokens(
      access:  res.data['access'],
      refresh: res.data['refresh'],
    );
    return Membre.fromJson(res.data['membre']);
  }

  Future<Membre> inscrire(Map<String, dynamic> data) async {
    final res = await _dio.post(ApiConfig.inscrire, data: data);
    return Membre.fromJson(res.data);
  }

  Future<Membre> getMoi() async {
    final res = await _dio.get(ApiConfig.moi);
    return Membre.fromJson(res.data);
  }

  Future<void> changerMotDePasse({
    required String ancienMdp,
    required String nouveauMdp,
    required String confirmation,
  }) async {
    await _dio.post(ApiConfig.changerMdp, data: {
      'ancien_mdp':  ancienMdp,
      'nouveau_mdp': nouveauMdp,
      'confirmation': confirmation,
    });
  }

  Future<void> logout() => StorageService.clearAll();
}
DART
ok "services/auth_service.dart"

cat > lib/services/membre_service.dart << 'DART'
import '../config/api_config.dart';
import '../models/cellule.dart';
import '../models/membre.dart';
import 'api_client.dart';

class MembreService {
  final _dio = ApiClient().dio;

  Future<List<Membre>> getMembres({
    String? cellule,
    String? role,
    String? search,
  }) async {
    final res = await _dio.get(ApiConfig.membres, queryParameters: {
      if (cellule != null) 'cellule': cellule,
      if (role    != null) 'role':    role,
      if (search  != null) 'search':  search,
    });
    final results = res.data['results'] ?? res.data;
    return (results as List).map((e) => Membre.fromJson(e)).toList();
  }

  Future<Membre> getMembre(int id) async {
    final res = await _dio.get('${ApiConfig.membres}$id/');
    return Membre.fromJson(res.data);
  }

  Future<Membre> modifierProfil(Map<String, dynamic> data) async {
    final res = await _dio.patch(ApiConfig.moi, data: data);
    return Membre.fromJson(res.data);
  }

  Future<List<Cellule>> getCellules() async {
    final res = await _dio.get(ApiConfig.cellules);
    final results = res.data['results'] ?? res.data;
    return (results as List).map((e) => Cellule.fromJson(e)).toList();
  }

  Future<void> toggleActiver(int id) async {
    await _dio.post('${ApiConfig.membres}$id/activer/');
  }
}
DART
ok "services/membre_service.dart"

cat > lib/services/evenement_service.dart << 'DART'
import '../config/api_config.dart';
import '../models/evenement.dart';
import 'api_client.dart';

class EvenementService {
  final _dio = ApiClient().dio;

  Future<List<Evenement>> getEvenements({String? statut, String? cellule}) async {
    final res = await _dio.get(ApiConfig.evenements, queryParameters: {
      if (statut  != null) 'statut':  statut,
      if (cellule != null) 'cellule': cellule,
    });
    final results = res.data['results'] ?? res.data;
    return (results as List).map((e) => Evenement.fromJson(e)).toList();
  }

  Future<Evenement> getEvenement(int id) async {
    final res = await _dio.get('${ApiConfig.evenements}$id/');
    return Evenement.fromJson(res.data);
  }

  Future<Evenement> creerEvenement(Map<String, dynamic> data) async {
    final res = await _dio.post(ApiConfig.evenements, data: data);
    return Evenement.fromJson(res.data);
  }

  Future<void> lancer(int id) async {
    await _dio.post('${ApiConfig.evenements}$id/lancer/');
  }

  Future<void> cloturer(int id) async {
    await _dio.post('${ApiConfig.evenements}$id/cloturer/');
  }

  Future<BilanEvenement> getBilan(int id) async {
    final res = await _dio.get('${ApiConfig.evenements}$id/bilan/');
    return BilanEvenement.fromJson(res.data);
  }

  Future<void> participer(int id) async {
    await _dio.post('${ApiConfig.evenements}$id/participer/');
  }

  Future<List<LigneBudget>> getBudget(int id) async {
    final res = await _dio.get('${ApiConfig.evenements}$id/budget/');
    return (res.data as List).map((e) => LigneBudget.fromJson(e)).toList();
  }

  Future<LigneBudget> ajouterLigneBudget(int id, Map<String, dynamic> data) async {
    final res = await _dio.post('${ApiConfig.evenements}$id/budget/', data: data);
    return LigneBudget.fromJson(res.data);
  }
}
DART
ok "services/evenement_service.dart"

cat > lib/services/cotisation_service.dart << 'DART'
import '../config/api_config.dart';
import '../models/cotisation.dart';
import 'api_client.dart';

class CotisationService {
  final _dio = ApiClient().dio;

  Future<List<Cotisation>> getCotisations() async {
    final res = await _dio.get(ApiConfig.cotisations);
    final results = res.data['results'] ?? res.data;
    return (results as List).map((e) => Cotisation.fromJson(e)).toList();
  }

  Future<List<Paiement>> getMesPaiements() async {
    final res = await _dio.get(ApiConfig.mesPaiements);
    return (res.data as List).map((e) => Paiement.fromJson(e)).toList();
  }

  Future<Paiement> payer(int cotisationId, Map<String, dynamic> data) async {
    final res = await _dio.post('${ApiConfig.cotisations}$cotisationId/payer/', data: data);
    return Paiement.fromJson(res.data);
  }

  Future<List<Paiement>> getPaiements(int cotisationId, {String? statut}) async {
    final res = await _dio.get(
      '${ApiConfig.cotisations}$cotisationId/paiements/',
      queryParameters: { if (statut != null) 'statut': statut },
    );
    return (res.data as List).map((e) => Paiement.fromJson(e)).toList();
  }

  Future<void> validerPaiement(int cotisationId, int paiementId, String statut, {String? note}) async {
    await _dio.post(
      '${ApiConfig.cotisations}$cotisationId/paiements/$paiementId/valider/',
      data: { 'statut': statut, if (note != null) 'note': note },
    );
  }
}
DART
ok "services/cotisation_service.dart"

# ═══════════════════════════════════════════════════════════════
# PROVIDERS
# ═══════════════════════════════════════════════════════════════

cat > lib/providers/auth_provider.dart << 'DART'
import 'package:flutter/material.dart';
import '../models/membre.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final _service = AuthService();

  AuthStatus _status = AuthStatus.initial;
  Membre?    _membre;
  String?    _error;

  AuthStatus get status      => _status;
  Membre?    get membre       => _membre;
  String?    get error        => _error;
  bool       get isLoggedIn   => _status == AuthStatus.authenticated;
  bool       get isLoading    => _status == AuthStatus.loading;
  bool       get isAdmin      => _membre?.isAdmin ?? false;

  Future<void> init() async {
    final token = await StorageService.getAccessToken();
    if (token == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      _membre = await _service.getMoi();
      _status = AuthStatus.authenticated;
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _status = AuthStatus.loading;
    _error  = null;
    notifyListeners();
    try {
      _membre = await _service.login(email, password);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error  = _parseError(e);
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> inscrire(Map<String, dynamic> data) async {
    _status = AuthStatus.loading;
    _error  = null;
    notifyListeners();
    try {
      _membre = await _service.inscrire(data);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error  = _parseError(e);
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _service.logout();
    _membre = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void refreshMembre(Membre membre) {
    _membre = membre;
    notifyListeners();
  }

  String _parseError(Exception e) {
    final msg = e.toString();
    if (msg.contains('401')) return 'Email ou mot de passe incorrect.';
    if (msg.contains('400')) return 'Données invalides.';
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return 'Impossible de joindre le serveur. Vérifie ta connexion.';
    }
    return 'Une erreur est survenue. Réessaie.';
  }
}
DART
ok "providers/auth_provider.dart"

cat > lib/providers/membre_provider.dart << 'DART'
import 'package:flutter/material.dart';
import '../models/membre.dart';
import '../models/cellule.dart';
import '../services/membre_service.dart';

class MembreProvider extends ChangeNotifier {
  final _service = MembreService();

  List<Membre>  _membres  = [];
  List<Cellule> _cellules = [];
  bool          _loading  = false;
  String?       _error;

  List<Membre>  get membres  => _membres;
  List<Cellule> get cellules => _cellules;
  bool          get loading  => _loading;
  String?       get error    => _error;

  Future<void> charger({String? search, String? cellule}) async {
    _loading = true; notifyListeners();
    try {
      _membres = await _service.getMembres(search: search, cellule: cellule);
      _error   = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<void> chargerCellules() async {
    _cellules = await _service.getCellules();
    notifyListeners();
  }

  Future<void> toggleActiver(int id) async {
    await _service.toggleActiver(id);
    await charger();
  }
}
DART
ok "providers/membre_provider.dart"

cat > lib/providers/evenement_provider.dart << 'DART'
import 'package:flutter/material.dart';
import '../models/evenement.dart';
import '../services/evenement_service.dart';

class EvenementProvider extends ChangeNotifier {
  final _service = EvenementService();

  List<Evenement>  _evenements = [];
  BilanEvenement?  _bilan;
  bool             _loading    = false;
  String?          _error;

  List<Evenement>  get evenements => _evenements;
  BilanEvenement?  get bilan      => _bilan;
  bool             get loading    => _loading;
  String?          get error      => _error;

  Future<void> charger({String? statut}) async {
    _loading = true; notifyListeners();
    try {
      _evenements = await _service.getEvenements(statut: statut);
      _error      = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<bool> participer(int evenementId) async {
    try {
      await _service.participer(evenementId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> chargerBilan(int id) async {
    _bilan   = await _service.getBilan(id);
    notifyListeners();
  }

  Future<bool> lancer(int id) async {
    try {
      await _service.lancer(id);
      await charger();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cloturer(int id) async {
    try {
      await _service.cloturer(id);
      await charger();
      return true;
    } catch (_) {
      return false;
    }
  }
}
DART
ok "providers/evenement_provider.dart"

cat > lib/providers/cotisation_provider.dart << 'DART'
import 'package:flutter/material.dart';
import '../models/cotisation.dart';
import '../services/cotisation_service.dart';

class CotisationProvider extends ChangeNotifier {
  final _service = CotisationService();

  List<Cotisation> _cotisations  = [];
  List<Paiement>   _mesPaiements = [];
  bool             _loading      = false;
  String?          _error;

  List<Cotisation> get cotisations  => _cotisations;
  List<Paiement>   get mesPaiements => _mesPaiements;
  bool             get loading      => _loading;
  String?          get error        => _error;

  Future<void> charger() async {
    _loading = true; notifyListeners();
    try {
      _cotisations  = await _service.getCotisations();
      _mesPaiements = await _service.getMesPaiements();
      _error        = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<bool> payer(int cotisationId, Map<String, dynamic> data) async {
    try {
      await _service.payer(cotisationId, data);
      await charger();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> validerPaiement(int cotisationId, int paiementId, String statut) async {
    await _service.validerPaiement(cotisationId, paiementId, statut);
    await charger();
  }
}
DART
ok "providers/cotisation_provider.dart"

# ═══════════════════════════════════════════════════════════════
# WIDGETS COMMUNS
# ═══════════════════════════════════════════════════════════════

cat > lib/widgets/statut_badge.dart << 'DART'
import 'package:flutter/material.dart';
import '../config/theme.dart';

class StatutBadge extends StatelessWidget {
  final String texte;
  final String type; // 'evenement' | 'paiement' | 'role'

  const StatutBadge({super.key, required this.texte, required this.type});

  Color get _color {
    switch (type) {
      case 'evenement': return texte.statutEvenementColor;
      case 'paiement':  return texte.statutPaiementColor;
      case 'role':      return texte.roleColor;
      default:          return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _color,
        ),
      ),
    );
  }
}
DART

cat > lib/widgets/loading_overlay.dart << 'DART'
import 'package:flutter/material.dart';
import '../config/theme.dart';

class LoadingOverlay extends StatelessWidget {
  final bool     isLoading;
  final Widget   child;

  const LoadingOverlay({super.key, required this.isLoading, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      if (isLoading)
        const ColoredBox(
          color: Colors.black26,
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
    ]);
  }
}
DART

cat > lib/widgets/empty_state.dart << 'DART'
import 'package:flutter/material.dart';
import '../config/theme.dart';

class EmptyState extends StatelessWidget {
  final String  message;
  final String? subMessage;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.message,
    this.subMessage,
    this.icon = Icons.inbox_outlined,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: AppTheme.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(message,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (subMessage != null) ...[
            const SizedBox(height: 8),
            Text(subMessage!,
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel ?? 'Réessayer')),
          ],
        ]),
      ),
    );
  }
}
DART
ok "widgets communs écrits"

# ═══════════════════════════════════════════════════════════════
# SCREENS — STUBS (compilables, à compléter)
# ═══════════════════════════════════════════════════════════════

# Helper pour créer un écran stub
make_screen() {
  local path=$1
  local class=$2
  local title=$3
  cat > "$path" << DART
import 'package:flutter/material.dart';

class $class extends StatelessWidget {
  const $class({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$title')),
      body: const Center(child: Text('$title — à implémenter')),
    );
  }
}
DART
}

make_screen_with_param() {
  local path=$1
  local class=$2
  local title=$3
  local param=$4
  local paramType=$5
  cat > "$path" << DART
import 'package:flutter/material.dart';

class $class extends StatelessWidget {
  final $paramType $param;
  const $class({super.key, required this.$param});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$title')),
      body: Center(child: Text('$title #\$$param')),
    );
  }
}
DART
}

# Auth screens
cat > lib/screens/auth/login_screen.dart << 'DART'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';

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
        SnackBar(content: Text(auth.error ?? 'Erreur de connexion'), backgroundColor: AppTheme.danger),
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
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(children: [
                // Logo / Titre
                const Icon(Icons.mosque_rounded, size: 72, color: AppTheme.primary),
                const SizedBox(height: 12),
                const Text('Mouhtacimina',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                const Text('Dahira Tidiane — UGB',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 40),

                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) => (v?.contains('@') ?? false) ? null : 'Email invalide',
                ),
                const SizedBox(height: 16),

                // Mot de passe
                TextFormField(
                  controller: _mdpCtrl,
                  obscureText: _mdpCache,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_mdpCache ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _mdpCache = !_mdpCache),
                    ),
                  ),
                  validator: (v) => (v?.length ?? 0) >= 6 ? null : 'Mot de passe trop court',
                ),
                const SizedBox(height: 28),

                // Bouton connexion
                ElevatedButton(
                  onPressed: auth.isLoading ? null : _submit,
                  child: auth.isLoading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Se connecter'),
                ),
                const SizedBox(height: 16),

                // Inscription
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text("Pas encore membre ? S'inscrire"),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
DART

make_screen "lib/screens/auth/register_screen.dart" "RegisterScreen" "Inscription"

# Membre screens
make_screen "lib/screens/membre/home_screen.dart"             "HomeScreen"            "Accueil"
make_screen "lib/screens/membre/profile_screen.dart"          "ProfileScreen"         "Mon profil"
make_screen "lib/screens/membre/edit_profile_screen.dart"     "EditProfileScreen"     "Modifier profil"
make_screen "lib/screens/membre/membres_screen.dart"          "MembresScreen"         "Membres"
make_screen "lib/screens/membre/evenements_screen.dart"       "EvenementsScreen"      "Événements"
make_screen "lib/screens/membre/cotisations_screen.dart"      "CotisationsScreen"     "Cotisations"

make_screen_with_param "lib/screens/membre/evenement_detail_screen.dart" \
  "EvenementDetailScreen" "Détail événement" "evenementId" "int"

# Admin screens
make_screen "lib/screens/admin/admin_dashboard_screen.dart"   "AdminDashboardScreen"  "Dashboard admin"
make_screen "lib/screens/admin/gestion_membres_screen.dart"   "GestionMembresScreen"  "Gestion membres"
make_screen "lib/screens/admin/creer_evenement_screen.dart"   "CreerEvenementScreen"  "Créer un événement"

make_screen_with_param "lib/screens/admin/valider_paiements_screen.dart" \
  "ValiderPaiementsScreen" "Valider paiements" "cotisationId" "int?"

make_screen_with_param "lib/screens/admin/bilan_evenement_screen.dart" \
  "BilanEvenementScreen" "Bilan événement" "evenementId" "int"

ok "Tous les écrans créés"

# ═══════════════════════════════════════════════════════════════
# MAIN.DART
# ═══════════════════════════════════════════════════════════════

cat > lib/main.dart << 'DART'
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/router.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/membre_provider.dart';
import 'providers/evenement_provider.dart';
import 'providers/cotisation_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MouhtaciminaApp());
}

class MouhtaciminaApp extends StatelessWidget {
  const MouhtaciminaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => MembreProvider()),
        ChangeNotifierProvider(create: (_) => EvenementProvider()),
        ChangeNotifierProvider(create: (_) => CotisationProvider()),
      ],
      child: Builder(builder: (context) {
        final auth   = context.watch<AuthProvider>();
        final router = buildRouter(auth);
        return MaterialApp.router(
          title:           'Mouhtacimina',
          debugShowCheckedModeBanner: false,
          theme:           AppTheme.light,
          routerConfig:    router,
        );
      }),
    );
  }
}
DART
ok "main.dart écrit"

# ─── FLUTTER PUB GET ─────────────────────────────────────────
log "Installation des packages Flutter..."
flutter pub get
ok "Packages installés"

# ─── VÉRIFICATION ────────────────────────────────────────────
log "Vérification du projet..."
flutter analyze --no-fatal-infos 2>/dev/null || warn "Quelques warnings d'analyse — normal pour les stubs"

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}   Flutter setup terminé !                           ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  ${BLUE}Lancer sur émulateur Android :${NC}"
echo "  cd $APP_NAME && flutter run"
echo ""
echo -e "  ${BLUE}Structure créée :${NC}"
echo "  lib/config/     → api_config, router, theme"
echo "  lib/models/     → cellule, membre, evenement, cotisation, paiement"
echo "  lib/services/   → api_client (dio+jwt), auth, membre, evenement, cotisation"
echo "  lib/providers/  → auth, membre, evenement, cotisation"
echo "  lib/screens/    → auth/ + membre/ + admin/ (stubs prêts à remplir)"
echo "  lib/widgets/    → statut_badge, loading_overlay, empty_state"
echo ""
echo -e "  ${YELLOW}Prochaine étape :${NC} implémenter les écrans un par un !"
echo ""
