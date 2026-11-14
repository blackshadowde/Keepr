// SPDX-License-Identifier: AGPL-3.0-or-later

//! ML-KEM-768 (FIPS 203) for Keepr's post-quantum layer, via libcrux.
//! Three C functions; every buffer has a fixed size (see the constants).
//! Each returns 0 on success, a negative number on failure.

use libcrux_ml_kem::mlkem768::{
    self, MlKem768Ciphertext, MlKem768PrivateKey, MlKem768PublicKey,
};

pub const PUBLIC_KEY_LEN: usize = 1184;
pub const PRIVATE_KEY_LEN: usize = 2400;
pub const CIPHERTEXT_LEN: usize = 1088;
pub const SECRET_LEN: usize = 32;

fn random<const L: usize>() -> Option<[u8; L]> {
    let mut b = [0u8; L];
    getrandom::fill(&mut b).ok()?;
    Some(b)
}

/// A new key pair: public key into `pk` (1184 bytes), private key into `sk`
/// (2400 bytes).
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_keygen(pk: *mut u8, sk: *mut u8) -> i32 {
    if pk.is_null() || sk.is_null() {
        return -1;
    }
    let Some(seed) = random::<64>() else { return -2 };
    let pair = mlkem768::generate_key_pair(seed);
    std::ptr::copy_nonoverlapping(pair.pk().as_ptr(), pk, PUBLIC_KEY_LEN);
    std::ptr::copy_nonoverlapping(pair.sk().as_ptr(), sk, PRIVATE_KEY_LEN);
    0
}

/// A fresh shared secret for the holder of `pk`: the ciphertext to send them
/// into `ct` (1088 bytes), the secret into `ss` (32 bytes). Fails (-3) on a
/// public key that isn't valid.
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_encapsulate(
    pk: *const u8,
    ct: *mut u8,
    ss: *mut u8,
) -> i32 {
    if pk.is_null() || ct.is_null() || ss.is_null() {
        return -1;
    }
    let mut key = [0u8; PUBLIC_KEY_LEN];
    std::ptr::copy_nonoverlapping(pk, key.as_mut_ptr(), PUBLIC_KEY_LEN);
    let key = MlKem768PublicKey::from(key);
    if !mlkem768::validate_public_key(&key) {
        return -3;
    }
    let Some(seed) = random::<32>() else { return -2 };
    let (c, s) = mlkem768::encapsulate(&key, seed);
    std::ptr::copy_nonoverlapping(c.as_ref().as_ptr(), ct, CIPHERTEXT_LEN);
    std::ptr::copy_nonoverlapping(s.as_ptr(), ss, SECRET_LEN);
    0
}

/// The shared secret from a ciphertext sent to us: `sk` (2400 bytes) and
/// `ct` (1088 bytes) in, the secret into `ss` (32 bytes).
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_decapsulate(
    sk: *const u8,
    ct: *const u8,
    ss: *mut u8,
) -> i32 {
    if sk.is_null() || ct.is_null() || ss.is_null() {
        return -1;
    }
    let mut key = [0u8; PRIVATE_KEY_LEN];
    std::ptr::copy_nonoverlapping(sk, key.as_mut_ptr(), PRIVATE_KEY_LEN);
    let key = MlKem768PrivateKey::from(key);
    let mut c = [0u8; CIPHERTEXT_LEN];
    std::ptr::copy_nonoverlapping(ct, c.as_mut_ptr(), CIPHERTEXT_LEN);
    let c = MlKem768Ciphertext::from(c);
    let s = mlkem768::decapsulate(&key, &c);
    std::ptr::copy_nonoverlapping(s.as_ptr(), ss, SECRET_LEN);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let mut pk = [0u8; PUBLIC_KEY_LEN];
        let mut sk = [0u8; PRIVATE_KEY_LEN];
        let mut ct = [0u8; CIPHERTEXT_LEN];
        let mut a = [0u8; SECRET_LEN];
        let mut b = [0u8; SECRET_LEN];
        unsafe {
            assert_eq!(keepr_pq_keygen(pk.as_mut_ptr(), sk.as_mut_ptr()), 0);
            assert_eq!(
                keepr_pq_encapsulate(pk.as_ptr(), ct.as_mut_ptr(), a.as_mut_ptr()),
                0
            );
            assert_eq!(
                keepr_pq_decapsulate(sk.as_ptr(), ct.as_ptr(), b.as_mut_ptr()),
                0
            );
        }
        assert_eq!(a, b);
        assert_ne!(a, [0u8; SECRET_LEN]);
    }

    #[test]
    fn wrong_key_gives_other_secret() {
        let mut pk = [0u8; PUBLIC_KEY_LEN];
        let mut sk = [0u8; PRIVATE_KEY_LEN];
        let mut sk2 = [0u8; PRIVATE_KEY_LEN];
        let mut pk2 = [0u8; PUBLIC_KEY_LEN];
        let mut ct = [0u8; CIPHERTEXT_LEN];
        let mut a = [0u8; SECRET_LEN];
        let mut b = [0u8; SECRET_LEN];
        unsafe {
            keepr_pq_keygen(pk.as_mut_ptr(), sk.as_mut_ptr());
            keepr_pq_keygen(pk2.as_mut_ptr(), sk2.as_mut_ptr());
            keepr_pq_encapsulate(pk.as_ptr(), ct.as_mut_ptr(), a.as_mut_ptr());
            keepr_pq_decapsulate(sk2.as_ptr(), ct.as_ptr(), b.as_mut_ptr());
        }
        assert_ne!(a, b);
    }

    #[test]
    fn bad_public_key_is_refused() {
        let pk = [0xffu8; PUBLIC_KEY_LEN];
        let mut ct = [0u8; CIPHERTEXT_LEN];
        let mut a = [0u8; SECRET_LEN];
        let r = unsafe { keepr_pq_encapsulate(pk.as_ptr(), ct.as_mut_ptr(), a.as_mut_ptr()) };
        assert_eq!(r, -3);
    }
}
