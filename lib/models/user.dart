class User {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;

  const User({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
  });

  String get fullName => [firstName, lastName].where((n) => n != null).join(' ');

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
      };
}
