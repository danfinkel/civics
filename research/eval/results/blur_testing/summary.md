# Real-World Image Quality Characterization — D01 SNAP Notice

## Dataset
- 34 real iPhone (or folder) photos
- 32 passing (response_deadline **exact** in ≥2/3 runs)
- 2 failing

## Key Finding
**center_edge_density** was the largest separable signal by effect size (Cohen's d = 1.569, p = 0.0321). The best single-attribute threshold rule reached ~88% accuracy on this corpus; optimizing `laplacian_variance` alone reached ~82%.

## Attribute Rankings
| attribute | pass mean | fail mean | Cohen's d | p-value | significant |
|---|---:|---:|---:|---:|:---:|
| center_edge_density | 0.03 | 0.016 | 1.569 | 0.0321 | yes |
| histogram_entropy | 4.83 | 5.103 | 1.471 | 0.1283 | no |
| white_region_ratio | 0.36 | 0.183 | 1.092 | 0.1497 | no |
| horizontal_blur_ratio | 1.018 | 3.362 | 1.035 | 0.1155 | no |
| frame_aspect_ratio | 0.75 | 0.656 | 1.0 | 0.0001 | yes |
| min_quadrant_luminance | 96.191 | 116.76 | 0.945 | 0.3922 | no |
| quadrant_luminance_variance | 1441.364 | 630.599 | 0.753 | 0.4706 | no |
| quadrant_luminance_ratio | 0.539 | 0.673 | 0.745 | 0.4706 | no |
| document_coverage_ratio | 0.039 | 0.004 | 0.697 | 0.2567 | no |
| shadow_ratio | 0.144 | 0.2 | 0.692 | 0.5338 | no |
| gradient_direction_entropy | 5.128 | 5.057 | 0.687 | 0.9708 | no |
| document_touches_edge | 0.844 | 0.5 | 0.61 | 0.2447 | no |
| tenengrad_variance | 3726.361 | 2406.644 | 0.573 | 0.4706 | no |
| tenengrad_variance_center | 5839.679 | 3748.502 | 0.562 | 0.4706 | no |
| document_center_offset | 0.058 | 0.079 | 0.506 | 0.3053 | no |
| mean_luminance | 148.239 | 142.846 | 0.307 | 0.9127 | no |
| noise_estimate | 3.001 | 2.745 | 0.178 | 0.6488 | no |
| rms_contrast | 0.269 | 0.265 | 0.166 | 1.0 | no |
| luminance_std | 68.681 | 67.493 | 0.166 | 1.0 | no |
| document_aspect_ratio | 0.839 | 0.908 | 0.163 | 0.9708 | no |
| laplacian_variance | 88.606 | 78.418 | 0.141 | 0.9127 | no |
| laplacian_variance_center | 138.587 | 125.148 | 0.107 | 0.8021 | no |
| edge_density | 0.02 | 0.019 | 0.064 | 1.0 | no |
| file_size_kb | 1916.469 | 1869.05 | 0.055 | 0.9697 | no |
| rotation_angle | 0.656 | 1.0 | 0.032 | 0.883 | no |
| michelson_contrast | 1.0 | 1.0 | 0.0 | 1.0 | no |


## Recommendation
Consider promoting **center_edge_density** with rule `pass if center_edge_density ≥ 0.02` 
