import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobileraker/features/auth/application/auth_notifier.dart';
import 'package:mobileraker/features/auth/domain/exceptions/auth_failure.dart';
import 'package:mobileraker/features/auth/domain/models/auth_user.dart';
import 'package:mobileraker/features/auth/domain/repositories/auth_repository.dart';

class FakeAuthRepository implements IAuthRepository {
  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  bool shouldFail = false;
  String failCode = 'invalid-credential';

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (shouldFail) {
      throw AuthFailure.fromCode(failCode);
    }
    _user = AuthUser(id: 'usr_123', email: email, displayName: 'Test User');
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (shouldFail) {
      throw AuthFailure.fromCode(failCode);
    }
    _user = AuthUser(id: 'usr_999', email: email, displayName: displayName);
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    if (shouldFail) {
      throw AuthFailure.fromCode(failCode);
    }
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

void main() {
  group('AuthController & IAuthRepository Contract', () {
    late FakeAuthRepository fakeRepo;
    late AuthController controller;

    setUp(() {
      fakeRepo = FakeAuthRepository();
      controller = AuthController(fakeRepo);
    });

    test('deve inicializar com estado de dados nulo', () {
      expect(controller.state, const AsyncValue<AuthUser?>.data(null));
    });

    test('deve realizar login com sucesso e atualizar o estado', () async {
      final success = await controller.signIn(
        email: 'dev@printdeck.io',
        password: 'password123',
      );

      expect(success, isTrue);
      expect(controller.state.hasValue, isTrue);
      expect(controller.state.value?.email, 'dev@printdeck.io');
      expect(controller.state.value?.displayName, 'Test User');
    });

    test('deve capturar falha de autenticação e expor AuthFailure tipada', () async {
      fakeRepo.shouldFail = true;
      fakeRepo.failCode = 'invalid-credential';

      final success = await controller.signIn(
        email: 'errado@printdeck.io',
        password: 'wrong',
      );

      expect(success, isFalse);
      expect(controller.state.hasError, isTrue);
      final error = controller.state.error;
      expect(error, isA<AuthFailure>());
      expect((error as AuthFailure).message, 'E-mail ou senha incorretos.');
    });

    test('deve realizar cadastro com displayName com sucesso', () async {
      final success = await controller.signUp(
        email: 'novo@printdeck.io',
        password: 'password123',
        displayName: 'Novo Usuário',
      );

      expect(success, isTrue);
      expect(controller.state.value?.displayName, 'Novo Usuário');
    });

    test('deve enviar e-mail de recuperação de senha com sucesso', () async {
      final success = await controller.sendPasswordResetEmail(
        email: 'reset@printdeck.io',
      );

      expect(success, isTrue);
      expect(controller.state.hasError, isFalse);
    });

    test('deve deslogar com sucesso', () async {
      await controller.signIn(email: 'dev@printdeck.io', password: '123');
      expect(controller.state.value, isNotNull);

      await controller.signOut();
      expect(controller.state.value, isNull);
    });
  });
}
