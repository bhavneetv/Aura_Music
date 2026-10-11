/// Admin Configuration for Aura Music
/// Replace [kAdminEmail] with your personal Firebase Auth email address.
/// Note: Real security is enforced in `firestore.rules`.
const String kAdminEmail = 'bhanu2006v@gmail.com';

const List<String> kAdminEmails = [
  'bhanu2006v@gmail.com',
];

/// Helper to check whether any given email string is a recognized admin email.
bool isConfiguredAdminEmail(String? email) {
  if (email == null) return false;
  final clean = email.trim().toLowerCase();
  if (clean.isEmpty) return false;
  return clean == kAdminEmail.trim().toLowerCase() ||
      kAdminEmails.any((e) => e.trim().toLowerCase() == clean);
}
