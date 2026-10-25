import 'package:cloud_firestore/cloud_firestore.dart';

/// A PIN profile with a scoped Firebase staff session. Position is descriptive;
/// common operational access and individually granted permissions are separate.
///
/// Lives at `shops/{shopId}/staff/{staffId}`.
enum StaffRole { owner, cashier, waiter, kitchen, manager }

extension StaffRoleX on StaffRole {
  String get label => switch (this) {
        StaffRole.owner => 'เจ้าของร้าน',
        StaffRole.cashier => 'แคชเชียร์',
        StaffRole.waiter => 'พนักงานเสิร์ฟ',
        StaffRole.kitchen => 'ครัว',
        StaffRole.manager => 'ผู้จัดการ',
      };
}

class StaffMember {
  final String id;
  final String name;

  /// Transient PIN input for owner edits; blank preserves the existing PIN.
  /// New credentials are salted/hashed on the server. Legacy plain PINs are
  /// migrated after successful authentication and never verified locally.
  final String pin;
  final StaffRole role;
  final bool active;
  final Map<String, bool> permissions;
  final DateTime createdAt;

  const StaffMember({
    required this.id,
    required this.name,
    required this.pin,
    this.role = StaffRole.cashier,
    this.active = true,
    this.permissions = const {},
    required this.createdAt,
  });

  factory StaffMember.fromFirestore(Map<String, dynamic> data, String id) =>
      StaffMember(
        id: id,
        name: data['name'] ?? '',
        pin: data['pin'] ?? '',
        role: StaffRole.values.firstWhere(
          (e) => e.name == (data['position'] ?? data['role'] ?? 'cashier'),
          orElse: () => StaffRole.cashier,
        ),
        active: data['active'] ?? true,
        permissions: {
          for (final e in (data['permissions'] as Map? ?? {}).entries)
            e.key as String: e.value == true
        },
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'pin': pin,
        'role': role.name,
        'position': role.name,
        'permissions': permissions,
        'active': active,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  StaffMember copyWith(
          {String? name,
          String? pin,
          bool? active,
          StaffRole? role,
          Map<String, bool>? permissions}) =>
      StaffMember(
        id: id,
        name: name ?? this.name,
        pin: pin ?? this.pin,
        role: role ?? this.role,
        permissions: permissions ?? this.permissions,
        active: active ?? this.active,
        createdAt: createdAt,
      );
}
