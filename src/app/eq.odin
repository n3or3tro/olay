package app
import "core:math"

Biquad_Coefficients :: struct { 
    b0, b1, b2, a1, a2: f64
}

compute_biquad_coefficients :: proc(freq_hz, q, gain, sample_rate:f64, type: EQ_Band_Type) -> Biquad_Coefficients {
    switch type {
    case .Bell:
        return compute_bell_coefficients(freq_hz, q, gain, sample_rate)
    case .High_Cut:
        return compute_highcut_coefficients(freq_hz, q, sample_rate)
    case .Low_Cut:
        return compute_lowcut_coefficients(freq_hz, q, sample_rate)
    case .High_Shelf:
        return compute_highshelf_coefficients(freq_hz, q, gain, sample_rate)
    case .Low_Shelf:
        return compute_lowshelf_coefficients(freq_hz, q, gain, sample_rate)
    case .Band_Pass:
        return compute_bandpass_coefficients(freq_hz, q, sample_rate)
    case .Notch:
        return compute_notch_coefficients(freq_hz, q, sample_rate)
    }
    panicf("Have not implemented filter for type {}", type)
}

compute_bell_coefficients :: proc(freq_hz, q, gain_db, sample_rate: f64) -> Biquad_Coefficients
{
    A := math.pow(10, gain_db / 40)
    w0 := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha := sin_w0 / (2 * q)

    b0 :=  1.0 + alpha * A
    b1 := -2.0 * cos_w0
    b2 :=  1.0 - alpha * A
    a0 :=  1.0 + alpha / A
    a1 := -2.0 * cos_w0
    a2 :=  1.0 - alpha / A

    // Normalize by a0
    return {
        b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}

compute_lowcut_coefficients :: proc(freq_hz, q, sample_rate:f64) -> Biquad_Coefficients 
{
    w0 := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha := sin_w0 / (2 * q)

    b0 :=  (1 + cos_w0) / 2
    b1 := -(1 + cos_w0)
    b2 :=  (1 + cos_w0) / 2
    a0 :=   1 + alpha
    a1 :=  -2 * cos_w0
    a2 :=   1 - alpha
    
    return Biquad_Coefficients { 
        b0 = b0 / a0,
        b1 = b1 / a0, 
        b2 = b2 / a0, 
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}

compute_highcut_coefficients :: proc(freq_hz, q, sample_rate:f64) -> 
Biquad_Coefficients 
{
    w0     := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha  := sin_w0 / (2 * q)

    b0 :=  (1 - cos_w0) / 2
    b1 :=   1 - cos_w0
    b2 :=  (1 - cos_w0) / 2

    a0 :=   1 + alpha
    a1 :=  -2 * cos_w0
    a2 :=   1 - alpha
    
    return Biquad_Coefficients { 
        b0 = b0 / a0,
        b1 = b1 / a0, 
        b2 = b2 / a0, 
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}

compute_highshelf_coefficients :: proc(freq_hz, q, gain_db, sample_rate: f64) -> Biquad_Coefficients 
{
    A := math.pow(10, gain_db / 40)
    w0 := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha := sin_w0 / (2 * q)
    
    b0 :=      A * ((A + 1) + (A - 1) * cos_w0 + 2 * math.sqrt(A) * alpha)
    b1 := -2 * A * ((A - 1) + (A + 1) * cos_w0)
    b2 :=      A * ((A + 1) + (A - 1) * cos_w0 - 2 * math.sqrt(A) * alpha)
    a0 :=           (A + 1) - (A - 1) * cos_w0 + 2 * math.sqrt(A) * alpha
    a1 :=      2 * ((A - 1) - (A + 1) * cos_w0)
    a2 :=           (A + 1) - (A - 1) * cos_w0 - 2 * math.sqrt(A) * alpha
    
    return Biquad_Coefficients {
        b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}

compute_lowshelf_coefficients :: proc(freq_hz, q, gain_db, sample_rate: f64) -> Biquad_Coefficients 
{
    A := math.pow(10, gain_db / 40)
    w0 := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha := sin_w0 / (2 * q)
    
    b0 :=      A * ((A + 1) - (A - 1) * cos_w0 + 2 * math.sqrt(A) * alpha)
    b1 :=  2 * A * ((A - 1) - (A + 1) * cos_w0)
    b2 :=      A * ((A + 1) - (A - 1) * cos_w0 - 2 * math.sqrt(A) * alpha)
    a0 :=           (A + 1) + (A - 1) * cos_w0 + 2 * math.sqrt(A) * alpha
    a1 :=     -2 * ((A - 1) + (A + 1) * cos_w0)
    a2 :=           (A + 1) + (A - 1) * cos_w0 - 2 * math.sqrt(A) * alpha
    
    return Biquad_Coefficients {
        b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}

compute_bandpass_coefficients :: proc(freq_hz, q, sample_rate: f64) -> Biquad_Coefficients 
{
    w0 := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha := sin_w0 / (2 * q)
    
    b0 :=  alpha
    b1 :=  0.0
    b2 := -alpha
    a0 :=  1.0 + alpha
    a1 := -2.0 * cos_w0
    a2 :=  1.0 - alpha
    
    return Biquad_Coefficients {
        b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}

compute_notch_coefficients :: proc(freq_hz, q, sample_rate: f64) -> Biquad_Coefficients 
{
    w0 := 2 * math.PI * freq_hz / sample_rate
    cos_w0 := math.cos(w0)
    sin_w0 := math.sin(w0)
    alpha := sin_w0 / (2 * q)
    
    b0 :=  1.0
    b1 := -2.0 * cos_w0
    b2 :=  1.0
    a0 :=  1.0 + alpha
    a1 := -2.0 * cos_w0
    a2 :=  1.0 - alpha
    
    return Biquad_Coefficients {
        b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0,
    }
}


// compute_magnitude_db :: proc(coeffs: Biquad_Coefficients, freq_hz, sample_rate: f64) -> f64 {
//     w      := 2 * math.PI * freq_hz / sample_rate
//     cos_w  := math.cos(w)
//     cos_2w := math.cos(2 * w)

//     b0, b1, b2 := coeffs.b0, coeffs.b1, coeffs.b2
//     a1, a2 := coeffs.a1, coeffs.a2

//     // |H(e^jw)|^2 = |B(e^jw)|^2 / |A(e^jw)|^2
//     num := b0*b0 + b1*b1 + b2*b2 + 2.0*(b0*b1 + b1*b2)*cos_w + 2.0*b0*b2*cos_2w
//     den := 1.0 + a1*a1 + a2*a2 + 2.0*(a1 + a1*a2)*cos_w + 2.0*a2*cos_2w
//     // den := 1.0 + a1*a1 + a2*a2 - 2.0*(a1 + a1*a2)*cos_w - 2.0*a2*cos_2w

//     magnitude := math.sqrt(num / den)
//     return 20.0 * math.log10(magnitude)
// }

compute_magnitude_db :: proc(coeffs: Biquad_Coefficients, freq_hz, sample_rate: f64) -> f64 {
    w := 2.0 * math.PI * freq_hz / sample_rate
    cos_w := math.cos(w)
    sin_w := math.sin(w)
    cos_2w := math.cos(2.0 * w)
    sin_2w := math.sin(2.0 * w)

    b0, b1, b2 := coeffs.b0, coeffs.b1, coeffs.b2
    a1, a2 := coeffs.a1, coeffs.a2

    // Direct form - numerically stable
    num_real := b0 + b1*cos_w + b2*cos_2w
    num_imag := b1*sin_w + b2*sin_2w
    den_real := 1.0 + a1*cos_w + a2*cos_2w
    den_imag := a1*sin_w + a2*sin_2w

    num := num_real*num_real + num_imag*num_imag
    den := den_real*den_real + den_imag*den_imag

    if den < 1e-20 {
        return -60.0
    }
    
    magnitude := math.sqrt(num / den)
    if magnitude < 1e-10 {
        return -60.0
    }
    return 20.0 * math.log10(magnitude)
}

generate_curve_points :: proc(coeffs: Biquad_Coefficients, sample_rate: f64) -> [256]f64 {
    curve: [256]f64
    min_freq := 20.0
    max_freq := 20000.0
    
    for i in 0..<256 {
        t    := f64(i) / 255.0
        freq := min_freq * math.pow(max_freq / min_freq, t)
        curve[i] = compute_magnitude_db(coeffs, freq, sample_rate)
    }
    return curve
}