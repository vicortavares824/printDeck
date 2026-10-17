class AuthFailure implements Exception {
  const AuthFailure(this.message, [this.code]);

  final String message;
  final String? code;

  factory AuthFailure.fromCode(String code, [String? customMessage]) {
    switch (code) {
      case 'invalid-email':
        return const AuthFailure('O endereço de e-mail informado é inválido.', 'invalid-email');
      case 'user-disabled':
        return const AuthFailure('Esta conta de usuário foi desativada.', 'user-disabled');
      case 'user-not-found':
        return const AuthFailure('Nenhum usuário encontrado com este e-mail.', 'user-not-found');
      case 'wrong-password':
      case 'invalid-credential':
        return const AuthFailure('E-mail ou senha incorretos.', 'invalid-credential');
      case 'email-already-in-use':
        return const AuthFailure('Este e-mail já está sendo utilizado por outra conta.', 'email-already-in-use');
      case 'operation-not-allowed':
        return const AuthFailure('O login por e-mail e senha não está habilitado no Firebase.', 'operation-not-allowed');
      case 'weak-password':
        return const AuthFailure('A senha informada é fraca. Utilize pelo menos 6 caracteres.', 'weak-password');
      case 'network-request-failed':
        return const AuthFailure('Falha de conexão. Verifique sua rede e tente novamente.', 'network-request-failed');
      case 'too-many-requests':
        return const AuthFailure('Muitas tentativas malsucedidas. Tente novamente mais tarde.', 'too-many-requests');
      default:
        return AuthFailure(
          customMessage ?? 'Ocorreu um erro durante a autenticação. Código: $code',
          code,
        );
    }
  }

  @override
  String toString() => message;
}
