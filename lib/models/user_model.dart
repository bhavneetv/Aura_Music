class UserModel {
  final String id;
  final String name;
  final String email;
  final String passwordHash;
  final String cloudSlotId;
  final int createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.cloudSlotId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'passwordHash': passwordHash,
      'cloudSlotId': cloudSlotId,
      'createdAt': createdAt,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      passwordHash: json['passwordHash']?.toString() ?? '',
      cloudSlotId: json['cloudSlotId']?.toString() ?? '',
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : int.tryParse(json['createdAt']?.toString() ?? '0') ?? 0,
    );
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? passwordHash,
    String? cloudSlotId,
    int? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      cloudSlotId: cloudSlotId ?? this.cloudSlotId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
