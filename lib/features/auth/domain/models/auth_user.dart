class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.isEmailVerified = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool isEmailVerified;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          displayName == other.displayName &&
          isEmailVerified == other.isEmailVerified;

  @override
  int get hashCode =>
      id.hashCode ^
      email.hashCode ^
      displayName.hashCode ^
      isEmailVerified.hashCode;

  @override
  String toString() {
    return 'AuthUser(id: $id, email: $email, displayName: $displayName, isEmailVerified: $isEmailVerified)';
  }
}
