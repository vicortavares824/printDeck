import '../models/auth_user.dart';

abstract class IAuthRepository {
  Stream<AuthUser?> get authStateChanges;

  AuthUser? get currentUser;

  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<AuthUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> sendPasswordResetEmail({
    required String email,
  });

  Future<void> updateDisplayName(String displayName);

  Future<void> signOut();
}
