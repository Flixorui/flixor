# SFace face model (X-Ray)

`SFace.mlpackage` is the SFace face-recognition model from the OpenCV Zoo
(`face_recognition_sface_2021dec.onnx`), converted to Core ML (float16) with
onnx2torch and coremltools. Its output matches the original ONNX model (cosine
similarity 1.0000 on test faces).

- Source: https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface
- Paper: Zhong et al., "SFace: Sigmoid-Constrained Hypersphere Loss for Robust Face Recognition", IEEE TIP 2021
- Licence: Apache License 2.0, https://www.apache.org/licenses/LICENSE-2.0

Input: a 112x112 RGB face (0-255) aligned to the ArcFace five-point template.
Output: a 128-number embedding; compare two with cosine similarity.

Faces are found with Apple's Vision framework (no extra model).
