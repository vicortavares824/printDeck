import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/exceptions/auth_failure.dart';
import '../domain/models/auth_user.dart';
import '../domain/repositories/auth_repository.dart';
import '../infrastructure/repositories/firebase_auth_repository.dart';

/// Provider que expõe o contrato abstrato do repositório de autenticação (DIP).
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return FirebaseAuthRepository();
});

/// Stream que emite o usuário autenticado em tempo real ou null se deslogado.
final authStateStreamProvider = StreamProvider<AuthUser?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.authStateChanges;
});

/// Notifier que gerencia as operações assíncronas de autenticação (Login, Cadastro e Reset).
class AuthController extends StateNotifier<AsyncValue<AuthUser?>> {
  AuthController(this._repository) : super(const AsyncValue.data(null));

  final IAuthRepository _repository;

  /// Realiza o login utilizando e-mail e senha.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = await _repository.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      state = AsyncValue.data(user);
      return true;
    } on AuthFailure catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(AuthFailure(e.toString()), st);
      return false;
    }
  }

  /// Realiza o cadastro de uma nova conta com e-mail, senha e nome opcional.
  Future<bool> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = await _repository.signUpWithEmailAndPassword(
        email: email,
        password: password,
        displayName: displayName,
      );
      state = AsyncValue.data(user);
      return true;
    } on AuthFailure catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(AuthFailure(e.toString()), st);
      return false;
    }
  }

  /// Envia e-mail de redefinição de senha para o endereço informado.
  Future<bool> sendPasswordResetEmail({
    required String email,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _repository.sendPasswordResetEmail(email: email);
      state = const AsyncValue.data(null);
      return true;
    } on AuthFailure catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(AuthFailure(e.toString()), st);
      return false;
    }
  }

  /// Atualiza o nome de exibição do usuário ativo.
  Future<bool> updateDisplayName(String displayName) async {
    state = const AsyncValue.loading();
    try {
      await _repository.updateDisplayName(displayName);
      state = AsyncValue.data(_repository.currentUser);
      return true;
    } on AuthFailure catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(AuthFailure(e.toString()), st);
      return false;
    }
  }

  /// Encerra a sessão ativa.
  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      await _repository.signOut();
      state = const AsyncValue.data(null);
    } on AuthFailure catch (e, st) {
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(AuthFailure(e.toString()), st);
    }
  }

  /// Limpa erros anteriores do estado.
  void clearError() {
    state = const AsyncValue.data(null);
  }
}

/// Provider do controlador de ações de autenticação.
final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthUser?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});

/// Provider síncrono do usuário atual
final currentUserProvider = Provider<AuthUser?>((ref) {
  final asyncUser = ref.watch(authStateStreamProvider);
  return asyncUser.valueOrNull ?? ref.watch(authRepositoryProvider).currentUser;
});
