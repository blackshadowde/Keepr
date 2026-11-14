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

pub const KEY_LEN: usize = 32;
pub const NONCE_LEN: usize = 12;
pub const TAG_LEN: usize = 16;

/// `len` random bytes from the system into `out`.
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_random(out: *mut u8, len: usize) -> i32 {
    if out.is_null() {
        return -1;
    }
    let buf = std::slice::from_raw_parts_mut(out, len);
    if getrandom::fill(buf).is_err() {
        return -2;
    }
    0
}

/// HKDF-SHA256 (no salt): 32 bytes from `ikm` and `info` into `out`.
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_hkdf(
    ikm: *const u8,
    ikm_len: usize,
    info: *const u8,
    info_len: usize,
    out: *mut u8,
) -> i32 {
    if ikm.is_null() || info.is_null() || out.is_null() {
        return -1;
    }
    let ikm = std::slice::from_raw_parts(ikm, ikm_len);
    let info = std::slice::from_raw_parts(info, info_len);
    let hk = hkdf::Hkdf::<sha2::Sha256>::new(None, ikm);
    let out = std::slice::from_raw_parts_mut(out, KEY_LEN);
    if hk.expand(info, out).is_err() {
        return -2;
    }
    0
}

/// AES-256-GCM: seals `pt` with `key` (32 bytes) and `aad`. A random nonce
/// goes into `nonce` (12 bytes); `ct` gets `pt_len + 16` bytes.
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_seal(
    key: *const u8,
    aad: *const u8,
    aad_len: usize,
    pt: *const u8,
    pt_len: usize,
    nonce: *mut u8,
    ct: *mut u8,
) -> i32 {
    use aes_gcm::aead::{Aead, KeyInit, Payload};
    if key.is_null() || aad.is_null() || pt.is_null() || nonce.is_null() || ct.is_null() {
        return -1;
    }
    let Some(n) = random::<NONCE_LEN>() else { return -2 };
    let cipher = aes_gcm::Aes256Gcm::new_from_slice(std::slice::from_raw_parts(key, KEY_LEN));
    let Ok(cipher) = cipher else { return -1 };
    let msg = Payload {
        msg: std::slice::from_raw_parts(pt, pt_len),
        aad: std::slice::from_raw_parts(aad, aad_len),
    };
    let Ok(out) = cipher.encrypt(aes_gcm::Nonce::from_slice(&n), msg) else {
        return -2;
    };
    if out.len() != pt_len + TAG_LEN {
        return -2;
    }
    std::ptr::copy_nonoverlapping(n.as_ptr(), nonce, NONCE_LEN);
    std::ptr::copy_nonoverlapping(out.as_ptr(), ct, out.len());
    0
}

/// AES-256-GCM: opens `ct` (`ct_len` bytes, tag at the end) into `pt`
/// (`ct_len - 16` bytes). -4 when it was changed or the key is wrong.
#[no_mangle]
pub unsafe extern "C" fn keepr_pq_open(
    key: *const u8,
    aad: *const u8,
    aad_len: usize,
    nonce: *const u8,
    ct: *const u8,
    ct_len: usize,
    pt: *mut u8,
) -> i32 {
    use aes_gcm::aead::{Aead, KeyInit, Payload};
    if key.is_null() || aad.is_null() || nonce.is_null() || ct.is_null() || pt.is_null() {
        return -1;
    }
    if ct_len < TAG_LEN {
        return -4;
    }
    let cipher = aes_gcm::Aes256Gcm::new_from_slice(std::slice::from_raw_parts(key, KEY_LEN));
    let Ok(cipher) = cipher else { return -1 };
    let msg = Payload {
        msg: std::slice::from_raw_parts(ct, ct_len),
        aad: std::slice::from_raw_parts(aad, aad_len),
    };
    let n = std::slice::from_raw_parts(nonce, NONCE_LEN);
    let Ok(out) = cipher.decrypt(aes_gcm::Nonce::from_slice(n), msg) else {
        return -4;
    };
    std::ptr::copy_nonoverlapping(out.as_ptr(), pt, out.len());
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_and_open() {
        let mut key = [0u8; KEY_LEN];
        let info = b"keepr-test";
        let ikm = [7u8; 32];
        unsafe {
            assert_eq!(keepr_pq_hkdf(ikm.as_ptr(), 32, info.as_ptr(), info.len(), key.as_mut_ptr()), 0);
        }
        let aad = b"room|sender";
        let pt = b"hello quantum world";
        let mut nonce = [0u8; NONCE_LEN];
        let mut ct = vec![0u8; pt.len() + TAG_LEN];
        let mut back = vec![0u8; pt.len()];
        unsafe {
            assert_eq!(
                keepr_pq_seal(key.as_ptr(), aad.as_ptr(), aad.len(), pt.as_ptr(), pt.len(), nonce.as_mut_ptr(), ct.as_mut_ptr()),
                0
            );
            assert_eq!(
                keepr_pq_open(key.as_ptr(), aad.as_ptr(), aad.len(), nonce.as_ptr(), ct.as_ptr(), ct.len(), back.as_mut_ptr()),
                0
            );
        }
        assert_eq!(&back[..], &pt[..]);
        // a changed byte, or other aad, is refused
        ct[0] ^= 1;
        let r = unsafe {
            keepr_pq_open(key.as_ptr(), aad.as_ptr(), aad.len(), nonce.as_ptr(), ct.as_ptr(), ct.len(), back.as_mut_ptr())
        };
        assert_eq!(r, -4);
        ct[0] ^= 1;
        let other = b"room|someone-else";
        let r = unsafe {
            keepr_pq_open(key.as_ptr(), other.as_ptr(), other.len(), nonce.as_ptr(), ct.as_ptr(), ct.len(), back.as_mut_ptr())
        };
        assert_eq!(r, -4);
    }

    #[test]
    fn hkdf_known_answer() {
        // RFC 5869 test case 3 (no salt, no info), first 32 bytes of OKM
        let ikm = [0x0bu8; 22];
        let mut out = [0u8; KEY_LEN];
        let info: [u8; 0] = [];
        unsafe {
            assert_eq!(keepr_pq_hkdf(ikm.as_ptr(), ikm.len(), info.as_ptr(), 0, out.as_mut_ptr()), 0);
        }
        let want = [
            0x8d, 0xa4, 0xe7, 0x75, 0xa5, 0x63, 0xc1, 0x8f, 0x71, 0x5f, 0x80, 0x2a, 0x06, 0x3c,
            0x5a, 0x31, 0xb8, 0xa1, 0x1f, 0x5c, 0x5e, 0xe1, 0x87, 0x9e, 0xc3, 0x45, 0x4e, 0x5f,
            0x3c, 0x73, 0x8d, 0x2d,
        ];
        assert_eq!(out, want);
    }

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
