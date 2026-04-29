# Real-World Image Quality Characterization — D01 SNAP Notice

## Dataset
- 34 real iPhone (or folder) photos
- 30 passing (response_deadline **exact** in ≥2/3 runs)
- 4 failing

## Key Finding
**histogram_entropy** was the largest separable signal by effect size (Cohen's d = 1.149, p = 0.0484). The best single-attribute threshold rule reached ~88% accuracy on this corpus; optimizing `laplacian_variance` alone reached ~76%.

## Attribute Rankings
| attribute | pass mean | fail mean | Cohen's d | p-value | significant |
|---|---:|---:|---:|---:|:---:|
| histogram_entropy | 4.816 | 5.07 | 1.149 | 0.0484 | yes |
| white_region_ratio | 0.368 | 0.213 | 1.07 | 0.1047 | no |
| quadrant_luminance_variance | 1507.678 | 538.624 | 0.948 | 0.1047 | no |
| quadrant_luminance_ratio | 0.53 | 0.669 | 0.885 | 0.2183 | no |
| min_quadrant_luminance | 95.217 | 113.78 | 0.826 | 0.4533 | no |
| horizontal_blur_ratio | 1.007 | 2.273 | 0.795 | 0.0577 | no |
| document_touches_edge | 0.867 | 0.5 | 0.771 | 0.0819 | no |
| mean_luminance | 149.021 | 139.678 | 0.758 | 0.2183 | no |
| center_edge_density | 0.03 | 0.023 | 0.752 | 0.1625 | no |
| frame_aspect_ratio | 0.75 | 0.703 | 0.707 | 0.0081 | yes |
| rotation_angle | -0.567 | 10.0 | 0.668 | 0.1971 | no |
| file_size_kb | 1870.5 | 2237.525 | 0.533 | 0.1313 | no |
| laplacian_variance_center | 134.484 | 162.641 | 0.269 | 0.5881 | no |
| document_coverage_ratio | 0.035 | 0.055 | 0.269 | 0.8974 | no |
| rms_contrast | 0.27 | 0.263 | 0.268 | 0.9794 | no |
| luminance_std | 68.814 | 67.09 | 0.268 | 0.9794 | no |
| gradient_direction_entropy | 5.126 | 5.107 | 0.246 | 0.1148 | no |
| tenengrad_variance | 3705.443 | 3223.386 | 0.235 | 0.9794 | no |
| document_center_offset | 0.06 | 0.051 | 0.209 | 0.8726 | no |
| noise_estimate | 2.966 | 3.141 | 0.149 | 0.7769 | no |
| document_aspect_ratio | 0.839 | 0.874 | 0.132 | 0.8099 | no |
| laplacian_variance | 87.609 | 90.992 | 0.052 | 0.6612 | no |
| tenengrad_variance_center | 5699.356 | 5846.511 | 0.045 | 0.6992 | no |
| edge_density | 0.02 | 0.02 | 0.024 | 0.7769 | no |
| shadow_ratio | 0.147 | 0.146 | 0.012 | 0.9361 | no |
| michelson_contrast | 1.0 | 1.0 | 0.0 | 1.0 | no |


## Recommendation
Consider promoting **histogram_entropy** with rule `pass if histogram_entropy < 5.14` 
