// SPDX-License-Identifier: AGPL-3.0-or-later

//! Sentence vectors for Bujji's notes: a small sentence model (ONNX) run
//! with tract, tokenized with the model's own tokenizer.json. One model is
//! loaded at a time and shared by every thread.

use std::ffi::{c_char, CStr};
use std::sync::Mutex;

use tokenizers::Tokenizer;
use tract_onnx::prelude::*;

/// Every text is padded or cut to this many tokens.
const LEN: usize = 128;

struct Model {
    plan: std::sync::Arc<TypedRunnableModel>,
    tok: Tokenizer,
    /// Input names in the model's order.
    inputs: Vec<String>,
}

static MODEL: Mutex<Option<Model>> = Mutex::new(None);

fn load(model: &str, tok: &str) -> Result<(), String> {
    let tok = Tokenizer::from_file(tok).map_err(|e| e.to_string())?;
    let mut m = tract_onnx::onnx()
        .model_for_path(model)
        .map_err(|e| e.to_string())?;
    let n = m.inputs.len();
    let mut names = Vec::new();
    for i in 0..n {
        let node = m.inputs[i].node;
        names.push(m.node(node).name.clone());
        m.set_input_fact(i, InferenceFact::dt_shape(i64::datum_type(), tvec![1, LEN]))
            .map_err(|e| e.to_string())?;
    }
    let plan = m
        .into_optimized()
        .and_then(|m| m.into_runnable())
        .map_err(|e| e.to_string())?;
    *MODEL.lock().map_err(|_| "lock".to_string())? = Some(Model { plan, tok, inputs: names });
    Ok(())
}

pub fn embed(text: &str) -> Result<Vec<f32>, String> {
    let guard = MODEL.lock().map_err(|_| "lock".to_string())?;
    let m = guard.as_ref().ok_or("no model")?;
    let enc = m.tok.encode(text, true).map_err(|e| e.to_string())?;
    let ids = enc.get_ids();
    let used = ids.len().min(LEN);
    let mut id = vec![0i64; LEN];
    let mut mask = vec![0i64; LEN];
    for i in 0..used {
        id[i] = ids[i] as i64;
        mask[i] = 1;
    }
    let types = vec![0i64; LEN];
    let mut feed: TVec<TValue> = tvec![];
    for name in &m.inputs {
        let v = if name.contains("mask") {
            mask.clone()
        } else if name.contains("type") {
            types.clone()
        } else {
            id.clone()
        };
        let t = tract_ndarray::Array2::from_shape_vec((1, LEN), v)
            .map_err(|e| e.to_string())?
            .into_tensor();
        feed.push(t.into());
    }
    let out = m.plan.run(feed).map_err(|e| e.to_string())?;
    let h = out[0].to_plain_array_view::<f32>().map_err(|e| e.to_string())?;
    let shape = h.shape().to_vec();
    if shape.len() != 3 {
        return Err(format!("unexpected output {:?}", shape));
    }
    let dims = shape[2];
    // mean of the real tokens, then unit length
    let mut v = vec![0f32; dims];
    for t in 0..used {
        for d in 0..dims {
            v[d] += h[[0, t, d]];
        }
    }
    let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt().max(1e-9);
    for x in v.iter_mut() {
        *x /= norm;
    }
    Ok(v)
}

fn cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

/// Loads a model and its tokenizer.json. 0 on success.
#[no_mangle]
pub unsafe extern "C" fn keepr_embed_load(model: *const c_char, tok: *const c_char) -> i32 {
    let (Some(m), Some(t)) = (cstr(model), cstr(tok)) else { return -1 };
    match load(m, t) {
        Ok(()) => 0,
        Err(_) => -2,
    }
}

/// Unloads the model (frees its memory).
#[no_mangle]
pub extern "C" fn keepr_embed_unload() {
    if let Ok(mut g) = MODEL.lock() {
        *g = None;
    }
}

/// The unit vector for `text` into `out` (room for `cap` floats). Returns
/// how many numbers it wrote, or a negative number on failure.
#[no_mangle]
pub unsafe extern "C" fn keepr_embed(text: *const c_char, out: *mut f32, cap: usize) -> i32 {
    let Some(t) = cstr(text) else { return -1 };
    if out.is_null() {
        return -1;
    }
    match embed(t) {
        Ok(v) if v.len() <= cap => {
            std::ptr::copy_nonoverlapping(v.as_ptr(), out, v.len());
            v.len() as i32
        }
        Ok(_) => -3,
        Err(_) => -2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cos(a: &[f32], b: &[f32]) -> f32 {
        a.iter().zip(b).map(|(x, y)| x * y).sum()
    }

    /// Needs a model: KEEPR_MODEL_DIR with model.onnx and tokenizer.json.
    #[test]
    #[ignore]
    fn matches_meaning() {
        let dir = std::env::var("KEEPR_MODEL_DIR").expect("KEEPR_MODEL_DIR");
        load(&format!("{dir}/model.onnx"), &format!("{dir}/tokenizer.json")).unwrap();
        let q = embed("how do I reach naren").unwrap();
        let phone = embed("naren phone number: 12257383929").unwrap();
        let bday = embed("gowthu birthday: 15 November").unwrap();
        let q2 = embed("when was gowthu born").unwrap();
        println!(
            "reach/phone {:.3} reach/bday {:.3} born/bday {:.3} born/phone {:.3}",
            cos(&q, &phone),
            cos(&q, &bday),
            cos(&q2, &bday),
            cos(&q2, &phone)
        );
        assert!(cos(&q, &phone) > cos(&q, &bday));
        assert!(cos(&q2, &bday) > cos(&q2, &phone));
    }
}
