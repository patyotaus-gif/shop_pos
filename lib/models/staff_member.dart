import 'package:cloud_firestore/cloud_firestore.dart';

/// A staff profile within a single shop login. Pokpok is single-account
/// per shop (one Firebase Auth user = the owner); "users" in the tier
/// feature list are PIN-based profiles under that one login, not separate
/// logins. This is how most Thai counter POS systems work: one device,
/// several staff who identify with a PIN so sales can be attributed and
/// the owner sees who rang what.
///
/// Lives at `shops/{shopId}/staff/{staffId}`.
enum StaffRole { owner, cashier }

extension StaffRoleX on StaffRole {
  String get label => switch (this) {
        StaffRole.owner => 'เจ้าของร้าน',
        StaffRole.cashier => 'พนักงาน',
      };
}

class StaffMember {
  final String id;
  final String name;

  /// 4-digit PIN used to switch the active staff on the POS. Stored as
  /// plain text — this is a low-stakes "who's at the till" marker, not a
  /// security boundary (the shop owner already controls the device + the
  /// Firebase login). Treated like a locker combo, not a password.
  final String pin;
  final StaffRole role;
  final bool active;
  final DateTime createdAt;

  const StaffMember({
    required this.id,
    required this.name,
    required this.pin,
    this.role = StaffRole.cashier,
    this.active = true,
    required this.createdAt,
  });

  factory StaffMember.fromFirestore(Map<String, dynamic> data, String id) =>
      StaffMember(
        id: id,
        name: data['name'] ?? '',
        pin: data['pin'] ?? '',
        role: StaffRole.values.firstWhere(
          (e) => e.name == (data['role'] ?? 'cashier'),
          orElse: () => StaffRole.cashier,
        ),
        active: data['active'] ?? true,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'pin': pin,
        'role': role.name,
        'active': active,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  StaffMember copyWith({String? name, String? pin, bool? active}) =>
      StaffMember(
        id: id,
        name: name ?? this.name,
        pin: pin ?? this.pin,
        role: role,
        active: active ?? this.active,
        createdAt: createdAt,
      );
}
