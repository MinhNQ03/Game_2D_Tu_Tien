# 10 — CI Failure Protocol (bắt buộc / mandatory)

> Steering: always included. Đây là GIAO THỨC BẮT BUỘC khi bất kỳ CI check nào trên
> GitHub (job **"Foundation gates (Godot 4.7)"**) thất bại — đặc biệt với test Godot chạy
> headless. Nó tồn tại vì một sự cố có thật: Phase 03 đã bị **5 commit "fix" đoán mò liên
> tiếp cùng một lỗi** trước khi tìm ra nguyên nhân gốc (xem `09-lessons-learned.md` L-016).
> **Điều đó không được phép lặp lại.**

## Luật tối thượng (the hard rule)

> **CẤM "đoán → push → chờ CI → đoán tiếp".** Mỗi lần push một bản sửa suy đoán mà
> không có bằng chứng nguyên nhân gốc là VI PHẠM giao thức này.

### CẬP NHẬT QUAN TRỌNG — tiền đề cũ của file này đã SAI (L-031)

File này từng mở đầu bằng *"Godot KHÔNG chạy được ở máy local (D-009), nên CI là nơi chạy
test thật duy nhất"*. **Điều đó không còn đúng, và thật ra chưa bao giờ được kiểm lại.**
D-009 là một kết luận từ Phase 0 (không tìm thấy Godot trên PATH của agent) và nó được
thừa hưởng suốt tám phase mà không ai thử lại. Khi thử: tải Godot 4.7-stable về là chạy
được ngay — headless, có display, chạy đủ cả 10 gate và chụp được screenshot thật.

**Hệ quả với giao thức này: BƯỚC 0 LÀ TÁI HIỆN LỖI Ở LOCAL, không phải đọc log CI.**
- Chạy đủ bộ gate ở local TRƯỚC khi push: lint → `--import` → `parse_check.gd` →
  `run_tests.gd` → 3 E2E. Một lỗi tái hiện được ở local không bao giờ nên trở thành một
  vòng CI.
- CI vẫn là **cơ quan xác nhận cuối cùng** (môi trường sạch, Godot do workflow pin), nên
  một commit vẫn chỉ "xong" khi check-run `Foundation gates (Godot 4.7)` là `success`.
  Nhưng CI không còn là nơi *phát hiện* lỗi.
- Phần còn lại của file vẫn nguyên giá trị: luật cấm "đoán → push → đoán tiếp", cách đọc
  lỗi thật, giới hạn push, và danh sách bẫy headless `-s` ở dưới. Chỉ có tiền đề "chỉ CI
  mới chạy được" là bị thay thế.

> Bài học tổng quát ở L-031: **một giới hạn công cụ mà bạn thừa hưởng từ lập luận của
> chính mình — chứ không từ một lỗi tool bạn vừa thấy — đáng được thử lại 10 phút trước
> khi để nó định hình cả quy trình.**

## Khi một CI check thất bại — làm ĐÚNG THỨ TỰ này

### Bước 1 — LẤY ĐƯỢC THÔNG ĐIỆP LỖI THẬT (không được bỏ qua)
Không bao giờ sửa khi chưa đọc được dòng lỗi thật. Lấy theo thứ tự ưu tiên:
1. Nếu người dùng dán log/ảnh lỗi → đọc kỹ từng dòng FAIL/ERROR trước khi làm gì khác.
2. Qua GitHub API (không cần auth):
   - Check-runs: `https://api.github.com/repos/MinhNQ03/Game_2D_Tu_Tien/commits/<sha>/check-runs`
     → lấy `conclusion`, `annotations_url`, và danh sách `steps` (step nào `failure`).
   - Annotations: `.../check-runs/<id>/annotations` → chứa dòng lỗi nếu CI phát annotation.
3. Nếu output lỗi KHÔNG đọc được qua API (chỉ thấy "exit code 1"): **sửa CI để nó in ra
   được, CHỈ MỘT LẦN** — tee stdout/stderr của gate ra `$GITHUB_STEP_SUMMARY` và/hoặc phát
   `::error::<dòng>` cho các dòng FAIL/ERROR/`SCRIPT ERROR`. Commit chẩn đoán này được phép
   (và chỉ) khi mục tiêu là ĐỌC được lỗi — sau khi fix xong phải GỠ scaffolding đó.

> Mọi test runner tự viết PHẢI in `[tag] [FAIL] <assertion>` + `[tag] RESULT: FAIL` và
> thoát mã khác 0. Mỗi assertion phải có message tự-mô-tả, nêu ĐÚNG mắt xích hỏng (ví dụ
> "interact actually changed the active map (was 'map_hub')"), không chỉ true/false.

### Bước 2 — TÌM NGUYÊN NHÂN GỐC (bằng đọc code, không phải đoán)
- Đọc đúng file liên quan đến dòng lỗi (ví dụ assertion fail ở E2E → đọc test + mọi node
  nó chạm: scene, script, autoload, signal). KHÔNG sửa code chưa đọc.
- Lần theo chuỗi dữ liệu/sự kiện: cái gì set giá trị đó? signal nào bắn? gate nào chặn?
  node nào bị free? Viết ra một câu nguyên nhân gốc rõ ràng TRƯỚC khi gõ sửa.
- Phân biệt: lỗi là ở **production code** hay ở **cách test mô phỏng môi trường**? Nếu 8/9
  gate xanh và chỉ 1 gate mới đỏ → gần như chắc chắn lỗi ở test mới, không phải code.
- Nghi ngờ các "bẫy môi trường headless `-s`" đã biết (xem L-016 và danh sách dưới) TRƯỚC
  khi nghi ngờ logic nghiệp vụ.

### Bước 3 — SỬA ĐÚNG MỘT LẦN
- Chỉ sửa khi đã xác định nguyên nhân gốc và giải thích được tại sao bản sửa chạm đúng nó.
- Nếu sửa làm cho test bớt "thật" (ví dụ bỏ qua một ranh giới) → phải ghi rõ đánh đổi, và
  nếu có thể, giữ ranh giới đó bằng một cơ chế xác định thay thế (ví dụ phát đúng signal
  thật thay cho va chạm vật lý headless).
- Chạy `get_diagnostics` trên mọi file đã sửa; sửa hết cảnh báo (line-length, narrowing,
  unused) trước khi push.

### Bước 4 — GIỚI HẠN PUSH (vòng ngắt)
- **Một bản sửa cho một nguyên nhân gốc.** Nếu đã push 2 lần cho CÙNG một lỗi mà vẫn đỏ:
  **DỪNG.** Không push lần 3. Thay vào đó:
  1. Thừa nhận với người dùng là cách tiếp cận chưa đúng.
  2. Quay lại Bước 1 — chắc chắn mình đang đọc đúng thông điệp lỗi thật, không phải đoán.
  3. Nếu lỗi không đọc được → ưu tiên commit chẩn đoán (Bước 1.3) THAY VÌ một bản fix đoán.
- Không bao giờ tạo nhiều commit "fix lỗi" gần giống nhau. Nếu lịch sử bắt đầu trông như
  "fix, fix again, fix again" → đó là tín hiệu đã vi phạm giao thức.

### Bước 5 — XÁC NHẬN XANH & DỌN SẠCH
- Sau khi CI xanh: xác minh `conclusion == "success"` qua API trên đúng SHA.
- Gỡ mọi scaffolding chẩn đoán đã thêm ở Bước 1.3 (trả CI step về bản sạch).
- Dọn mọi file scratch (`_*.ps1`, `_*.log`, …) — L-009.
- Nếu lỗi thuộc một lớp có thể tái diễn → thêm một mục `L-0NN` vào `09-lessons-learned.md`.

## Bẫy môi trường headless Godot `-s` (nghi trước tiên)
Test E2E chạy bằng `godot --headless --path . -s res://tests/e2e/<runner>.gd` KHÔNG có cửa
sổ game và KHÔNG có vòng lặp game đầy đủ. Vì vậy:
- **Area2D `body_entered`/`area_entered` không bắn tin cậy** khi di chuyển/teleport body →
  đừng phụ thuộc va chạm vật lý để kích hoạt một đường đi. Thay bằng **emit chính signal
  thật của node** (`node.emit_signal("body_entered", other)`) để chạy đúng handler thật.
- **`_unhandled_input` không được bơm qua viewport** như game thật → gọi trực tiếp
  `node._unhandled_input(event)` khi cần, SAU khi đã set trạng thái input.
- **Thời điểm `Input.is_action_just_pressed` sau `Input.action_press` rất mong manh** →
  dùng vòng lặp thử có giới hạn (press → dispatch → kiểm tra hiệu ứng → sang frame → thử
  lại), đừng đoán đúng một frame duy nhất.
- `_process`/`_physics_process` của node KHÔNG tự chạy đều như game — phải `await
  scene_tree.process_frame` / `physics_frame` một cách có chủ đích.
- Autoload là LIVE dưới `/root` ngay cả trong runner (D-019/L-010) — test đơn vị/tích hợp
  dùng instance `Script.new()`, chỉ E2E tiến-trình-riêng mới được chạm singleton thật.
- `class_name` chéo file báo "Could not find type" ở LSP local là do cache
  `.godot/global_script_class_cache.cfg` (gitignored) chưa refresh — KHÔNG phải lỗi thật;
  bước `--import` của CI đăng ký class_name trước khi parse.

## Tóm tắt một dòng
> Lỗi CI = **đọc lỗi thật → tìm nguyên nhân gốc bằng đọc code → sửa đúng một lần → nếu 2
> lần vẫn đỏ thì dừng và chẩn đoán lại, KHÔNG đoán tiếp**. Không bao giờ rải commit fix lởm.
