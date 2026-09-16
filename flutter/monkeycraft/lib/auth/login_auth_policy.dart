enum LoginAuthMode { pair, password }

class LoginAuthPolicy {
  static LoginAuthMode defaultMode({
    required bool hasPassword,
    required bool addressPairingEligible,
  }) {
    if (hasPassword) {
      return LoginAuthMode.password;
    }
    if (addressPairingEligible) {
      return LoginAuthMode.pair;
    }
    return LoginAuthMode.password;
  }

  static bool showPasswordField({
    required LoginAuthMode mode,
    required bool hasPassword,
  }) {
    return hasPassword || mode == LoginAuthMode.password;
  }

  static bool pairIfNeeded({
    required LoginAuthMode mode,
    required bool hasPassword,
    required bool tailscalePath,
  }) {
    if (hasPassword) {
      return false;
    }
    if (tailscalePath) {
      return true;
    }
    return mode == LoginAuthMode.pair;
  }

  static bool requirePasswordBeforeConnect({
    required LoginAuthMode mode,
    required bool hasPassword,
    required bool tailscalePath,
  }) {
    if (hasPassword || tailscalePath) {
      return false;
    }
    return mode == LoginAuthMode.password;
  }
}
