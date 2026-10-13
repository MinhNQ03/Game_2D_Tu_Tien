# Aetheria — cách làm một task (đọc trước MỌI yêu cầu)

Godot 4.7 · 2D top-down pixel-art xianxia RPG. File này được nạp tự động mỗi phiên.

Nó gồm hai phần:

- **Phần A (mục 1–9): cách làm việc.** Áp dụng cho bất kỳ task code nào, ở bất kỳ dự án nào. Đây
  là quy trình đã dùng qua D-057B → D-073 và các gate pre-Phase-21; mỗi quy tắc có lý do là một
  lỗi thật đã xảy ra.
- **Phần B (mục 10–14): riêng dự án này.** Kiến trúc, lệnh, bẫy môi trường, tài liệu chủ.

Khi file này mâu thuẫn với tài liệu chủ (mục 14) hoặc canon: tài liệu chủ thắng, rồi sửa lại file
này. Khi mâu thuẫn với brief người dùng đang giao: brief thắng trong phạm vi của nó.

Trả lời người dùng bằng **tiếng Việt**. Code, comment, commit, docs trong repo bằng tiếng Anh.

---

# PHẦN A — CÁCH LÀM VIỆC

## 1. Năm nguyên tắc gốc

1. **Sự thật lấy từ hiện trạng, không lấy từ trí nhớ.** Summary, SHA, báo cáo cũ — kể cả của chính
   mình — chỉ là gợi ý. Đọc lại `git`, code, log, CI trước khi tin.
2. **Chưa tái hiện được thì chưa sửa.** Mọi lỗi phải thấy nó đỏ trước, bằng test hoặc phép đo, rồi
   mới đổi code. "Đọc code thấy có vẻ sai" không phải bằng chứng.
3. **Sửa ở chủ sở hữu của vấn đề.** Không vá ở chỗ triệu chứng lộ ra (nới ngưỡng, thêm retry, thêm
   sleep, tăng giới hạn, bỏ assert).
4. **Xanh chưa phải xong.** Xong = có bằng chứng đúng loại: test bắt được lỗi, app thật đã chạy,
   ảnh đã mở ra nhìn, CI xanh trên đúng SHA.
5. **Nói đúng những gì đã làm.** Cái đã kiểm, cái chưa kiểm, cái không kiểm được — tách bạch.

Cấm: `đoán → code → test xanh → báo xong`.

## 2. Quy trình một task, từng bước

```
PREFLIGHT → ĐỌC → CHỐT PHẠM VI → TÁI HIỆN / ĐO → ROOT CAUSE → TEST ĐỎ → SỬA → TEST XANH
→ MUTATION → GATE ĐẦY ĐỦ → APP THẬT + NHÌN → TỰ REVIEW DIFF → DOCS → COMMIT → PUSH
→ CI TRÊN ĐÚNG SHA → BÁO CÁO → DỪNG
```

### 2.1 Preflight (mỗi phiên, mỗi task)

- `git fetch --all --prune`, `git status --short`, nhánh hiện tại, `git log -5`, SHA của `main` và
  các nhánh liên quan, `gh run list` để biết CI trên SHA nào xanh.
- Working tree có thay đổi lạ: đọc diff, không ghi đè, không stash, không stage. File không rõ chủ
  (ở đây: `CLAUDE.md`, `.kiro/settings/`) để nguyên.
- Tạo nhánh từ **SHA cụ thể**: `git switch -c <tên> <sha>`, rồi đọc `git log -1` **sau** khi chuyển.
  (Đã từng: checkout bị đổi giữa hai lệnh, nhánh tách nhầm gốc, chạy cả một lượt gate trên cây
  sai. Lộ ra nhờ số test lệch 1241 ≠ 1248.)
- Ghi lại baseline: số test pass, hành vi hiện tại của thứ sắp sửa. Một con số lệch với lần trước
  là một phát hiện, không phải nhiễu.

### 2.2 Đọc

- Đọc brief đến hết, kể cả phần cấm và phần dừng. Brief có checkpoint (`APPROVED`, `SIGN-OFF`, "dừng
  sau gate này") thì **dừng đúng chỗ đó**.
- Đọc code thật của vùng sắp đụng theo mục 3b: chủ sở hữu state, ai gọi nó, ai nghe tín hiệu của
  nó, test hiện có của nó. Đọc phần tài liệu chủ liên quan (mục 14). Xây thứ mới thì trả lời năm
  câu của mục 3c trước khi code.
- Với lỗi: đọc **log gốc của lần hỏng**, không đọc mô tả của người khác về nó. Chú ý cả assert nào
  **qua**: "3 assert đỏ nhưng assert máu-không-đổi lại xanh" đã chỉ ra đúng nguyên nhân.

### 2.3 Chốt phạm vi

- Viết ra (trong đầu hoặc một dòng cho người dùng): việc này đổi cái gì, không đổi cái gì.
- Mục đã đóng thì **kiểm lại như hồi quy**, không làm lại. Chỉ sửa khi tái hiện được lỗi mới.
- Người dùng nói "fix hết nợ": làm hết phần một công cụ làm được; phần cần thứ chưa tồn tại (nội
  dung của phase sau, người chơi thật, quyết định thiết kế) thì nói rõ vì sao để lại.
- Quyết định là của người dùng (đổi luật thiết kế, merge, xoá): hỏi một lần, rồi làm tiếp phần
  không phụ thuộc câu trả lời với lựa chọn mặc định an toàn nhất, và ghi rõ đã chọn gì.

### 2.4 Tái hiện và đo

- Viết **script dò** trong thư mục scratch (ngoài repo, không commit). Chạy app/hệ thống thật, in
  ra trạng thái từng bước. Rẻ, nhanh, vứt được.
- Lỗi "thỉnh thoảng": tìm **biến số khác nhau giữa lần đỏ và lần xanh**, rồi ép biến đó. Ví dụ đã
  dùng: nghi phụ thuộc thời gian thực → ép `--fixed-fps N` quét từ 5 đến 100000 → lỗi "ngẫu nhiên"
  thành một bảng số, và giá trị ≤ 0,1 ms cho đúng chữ ký lỗi trên CI.
- Hỏi của mọi hàm không nhận tham số thời gian/ngẫu nhiên: **nó đọc đồng hồ / nguồn ngẫu nhiên của
  ai?** Một lời gọi engine có delta ngầm là phụ thuộc wall-clock cho tới khi chứng minh ngược lại.
- Khi có bảng số: phát biểu nguyên nhân bằng một câu kiểm chứng được, kèm cái **chưa** đo được.

### 2.5 Root cause

- Một root cause tốt trả lời được: vì sao hỏng, **vì sao test cũ không bắt**, và lỗi cùng loại còn
  ở đâu nữa. Câu thứ ba luôn phải đi tìm (đã từng: 1 test hỏng → 20 test ở 5 file cùng lỗi; 1 chủ
  sở hữu có lỗ hổng re-entry → 4 chủ khác cũng có).
- Sau 3 vòng sửa → kiểm mà chưa rõ: dừng, báo đã loại trừ gì. Không đổi hướng liều hơn.

### 2.6 Test đỏ → sửa → xanh

- Viết test tái hiện đúng lỗi **trước**, chạy thấy đỏ với đúng thông điệp mong đợi, rồi mới sửa.
- Sửa nhỏ nhất đủ đúng, ở chủ sở hữu. Không refactor kèm, không framework "cho tương lai".
- Xanh rồi: chạy lại các test lân cận, không chỉ test vừa viết.

### 2.7 Mutation (test-the-test)

- Với mỗi bảo vệ vừa thêm: **gỡ nó ra** (một sửa đổi nhỏ, tự động bằng script thay chuỗi), chạy
  test liên quan, phải đỏ; rồi khôi phục. Ghi: áp dụng bao nhiêu, bắt bao nhiêu, cái nào sống.
- Mutation **sống** là thông tin: hoặc test thiếu (viết thêm, chạy lại), hoặc mutation tương đương
  (nói rõ vì sao). Không thổi số bằng mutation trùng nhau. Không giấu cái sống.

### 2.8 Gate đầy đủ

- Chạy toàn bộ: lint, import, parse, boot, cả suite, mọi E2E, validator nội dung. Dùng **một script
  chạy tuần tự, ghi log ra file, in bảng tóm tắt** — không gõ tay từng lệnh mỗi lần.
- Luôn đếm `SCRIPT ERROR` trong log: test crash vẫn có thể in PASS.
- Việc lâu thì chạy nền, làm việc khác không tranh tài nguyên (không chạy hai thứ cần cửa sổ / cần
  đo thời gian cùng lúc).

### 2.9 App thật và nhìn (nếu có gì người dùng thấy được)

- Chạy app thật trong cửa sổ thật, chụp, **mở ảnh ra xem** và mô tả cụ thể thấy gì. Ảnh chưa mở
  không phải bằng chứng. Mọi tổ hợp ngôn ngữ × kích thước của bề mặt mới đều mở, không lấy mẫu:
  ngôn ngữ thứ hai là nơi layout vỡ (đã từng: "Travelling c…" chỉ có ở bản tiếng Anh).
- Lỗi thấy bằng mắt cũng thành test trước khi sửa.

### 2.10 Review diff, docs, commit, push, CI

- Đọc lại toàn bộ `git diff` như người khác viết: dòng thừa, comment sai sự thật, số liệu bịa.
- Docs: cập nhật tài liệu chủ đang có, không tạo tài liệu song song. Mỗi lỗi ghi theo chuỗi
  `BUG → ROOT CAUSE → VÌ SAO TEST CŨ SÓT → BẤT BIẾN → TEST`. Lịch sử có ngày tháng thì **giữ
  nguyên**, thêm mục "hiện trạng" có ngày chứ không sửa quá khứ.
- Commit theo mục 6. Push nhánh, chờ CI, đọc lại bằng `gh`: đúng SHA, attempt thứ mấy, số test.
- Báo cáo theo mục 7. Rồi **dừng** nếu brief bảo dừng.

## 3. Cách suy nghĩ khi phân tích

Các câu hỏi luôn đặt ra, theo thứ tự:

1. **Ai sở hữu state này?** Sửa ở đó. UI/presentation chỉ đọc.
2. **Điểm không thể quay lại nằm ở đâu?** Liệt kê từng dòng một hàm "transactional" làm trước điểm
   commit và hỏi: dòng này hoàn tác được không? Cái không hoàn tác được phải dời ra sau điểm commit
   hoặc được hỏi trước. Test rollback phải assert state của **các chủ khác**, không chỉ thứ được
   khôi phục.
3. **Ai đang nghe, và họ chạy lúc nào?** Handler của signal chạy **bên trong** lời gọi phát ra nó.
   Chủ nào nhờ chủ khác làm việc giữa lúc đang ghi thì phải từ chối ghi lồng trong cửa sổ đó. Chủ
   nào ghi xong state của mình rồi mới phát signal thì không cần.
4. **Đường thất bại để lại gì?** Từ chối ở bước đầu dễ; hãy cho hỏng ở hệ quả **thứ hai / cuối
   cùng**. Sau một lần từ chối, hệ thống còn trả lời tiếp không?
5. **Lặp lại / sai thời điểm thì sao?** Bấm hai lần, gọi lại từ bên trong, giữa animation, sau khi
   chết, khi modal mở, ở ngôn ngữ kia, ở biên.
6. **Kết luận suy ra từ sự kiện có nêu đủ điều kiện của chủ thể không?** ("đứng lại chiến đấu" cần
   một người còn đứng.)
7. **Nó có chạm tới người dùng với nội dung đang ship không?** Dò dữ liệu thật để trả lời, và báo
   đúng mức độ: "đang xảy ra", "cách một lần sửa nội dung", hay "chỉ khi file hỏng".
8. **Giải pháp nào bị loại và vì sao?** Ghi lại ít nhất phương án hiển nhiên nhất đã không chọn.

## 3b. Cách đọc code (trước khi sửa bất cứ thứ gì)

Đọc để trả lời câu hỏi, không đọc từ trên xuống. Làm theo thứ tự này:

1. **Tìm chỗ vào.** Từ thứ người dùng thấy hoặc log báo lỗi, `grep` tên hàm / signal / chuỗi hiển
   thị để tới đúng file. Không đoán đường dẫn.
2. **Liệt kê hàm công khai của file đó trước** (`grep -n "^func \|^signal \|^const "`), rồi mới
   đọc thân những hàm liên quan. Một file 800 dòng thường chỉ có 60 dòng cần đọc kỹ.
3. **Lần theo MỘT giá trị từ đầu đến cuối.** Ví dụ một phím bấm: input → runtime → domain → state
   → signal → view → control. Ghi ra từng trạm và ai sở hữu nó. Lỗi thường nằm giữa hai trạm.
4. **Tìm mọi chỗ gọi và mọi chỗ nghe** trước khi đổi một hàm hay một signal
   (`grep -rn "tên_hàm\|tên_signal.connect"`). Đổi chữ ký mà chưa biết ai gọi là đoán.
5. **Đọc test hiện có của nó.** Test nói hành vi nào đang được ghim, và — quan trọng hơn — **cái gì
   chưa ai kiểm**. Một bảo vệ được tài liệu nhắc tới mà không có test thì coi như chưa có (đã
   từng: "router từ chối yêu cầu lồng" có trong tài liệu, không có test, mutation sống).
6. **Đọc comment "vì sao" và lịch sử của dòng lạ** (`git log -L`, `git blame`) trước khi cho là nó
   thừa. Một dòng trông vô lý thường là vết của một lỗi cũ.
7. **Đọc tới đáy lời gọi.** Hàm của mình gọi hàm engine / thư viện thì hỏi: hàm đó đọc gì mà mình
   không truyền vào (đồng hồ, trạng thái toàn cục, thứ tự cây)? (Đã từng: mọi người đọc `tick(delta)`
   và kết luận "delta cố định"; không ai đọc tới `move_and_slide()` ở cuối, thứ không nhận delta.)
8. **Nghi thì chạy, đừng suy.** Một script dò 30 dòng in trạng thái thật rẻ hơn một giờ lý luận, và
   không thể sai theo cách lý luận sai.

Dấu hiệu chưa đọc đủ: không nói được ai sở hữu state mình sắp đổi; không kể được ai sẽ chạy khi
signal này phát; định sửa ở chỗ lỗi **hiện ra** thay vì chỗ nó **sinh ra**.

## 3c. Thiết kế trước khi xây một thứ mới

Sửa lỗi bắt đầu bằng tái hiện; xây mới bắt đầu bằng năm câu trả lời, viết ra trước khi gõ code:

1. **Người dùng sẽ thấy / làm được gì khác đi?** Một câu. Không viết được câu này thì chưa hiểu việc.
2. **Dữ liệu từ đâu tới?** Mỗi dữ kiện hiển thị lấy từ **một** feed đã có. Cần dữ kiện mới thì
   thêm vào view của đúng chủ sở hữu; không tính lại ở UI, không tạo nguồn thứ hai. (Thẻ nhân vật:
   hình và đồ mặc từ `InventoryView`, chỉ số từ `ChronicleView` — không thêm chủ sở hữu nào.)
3. **Dùng lại được gì?** Tìm thành phần đang làm đúng việc đó (sprite component, ô icon, stylebox)
   trước khi viết cái mới. Vẽ lại thứ đã có là tạo hai phiên bản sẽ lệch nhau.
4. **Nó chạm vào luật nào?** Giới hạn HUD, modal, hiệu năng mỗi frame, bản địa hoá, canon. Luật nào
   thuộc quyền người dùng thì giữ nguyên và nêu ra, không tự đổi.
5. **Phương án nào bị loại, vì sao?** Ít nhất phương án hiển nhiên nhất. Ghi vào commit / docs.

Rồi làm theo **lát mỏng chạy được**: bản nhỏ nhất hiện lên màn hình thật → chụp → nhìn → sửa →
mới mở rộng. Không viết xong cả thiết kế rồi mới chạy lần đầu. Mỗi lát: test cho bất biến của nó,
và test cho từng lỗi mà việc nhìn ảnh phát hiện ra.

## 4. Cách viết code

- **Khớp với code xung quanh** trước mọi sở thích riêng: cách đặt tên, mật độ comment, idiom,
  cách chia file. Mở hai file hàng xóm ra xem trước khi viết file mới. Quy ước của dự án ở mục 10b.
- **Comment giải thích vì sao**, và lỗi nào đã sinh ra dòng này; không kể lại code làm gì. Comment
  phải đúng sự thật: không viết con số hay câu chuyện chưa kiểm ("chạy xanh cả năm"). Con số trong
  comment / docs được dán từ một lần chạy, không gõ trước khi đo (đã từng: comment "đo được 0,60 /
  0,55 / 0,42" viết trước khi đo; số thật là 0,51 / 0,54 / 0,45 và ngược hẳn kết luận).
- **Một hàm một việc.** Hàm cần comment chia đoạn để hiểu thì tách ra. Khi thêm nhánh thứ ba vào
  một hàm đã dài, tách phần "làm" thành hàm riêng có tên nói được việc nó làm.
- **Tên nói ý định**, không nói cách làm: `transition_refusal()`, `slot_name_is_whole()`. Boolean
  đọc như mệnh đề (`is_`, `can_`, `has_`). Signal ở thì quá khứ.
- **Thất bại phải to**: `assert()` cho lỗi lập trình, `push_error()` cho lỗi nội dung / phục hồi
  được; trả về lý do từ chối có tên, không trả `false` trơn khi người gọi cần biết vì sao. Không
  nuốt một lần load hỏng hay một null không được phép null.
- **Kiểm ở biên** (dữ liệu nạp vào, payload, nội dung ngoài), không rải kiểm tra khắp bên trong.
- **Không lặp logic**: trích ra khi cùng logic xuất hiện lần thứ hai — không sớm hơn.
- Setter chỉ **lưu**; một hàm refresh **ghi** ra control — và refresh chạy cả từ `_ready`. Một
  thành phần có thể được cấp dữ liệu trước khi nó vào cây.
- Số, màu, kích thước là hằng có tên ở đúng chỗ của nó; màn hình không tự dựng style.
- Tất định: không ngẫu nhiên ngoài stream có seed, không phụ thuộc thứ tự set/hash, không đồng hồ
  thật trong logic.
- Không polling mỗi frame; thứ không nhìn thấy thì không xử lý.
- Từ chối do lời gọi lồng (không người dùng nào gây ra được) thì **trả về, không thông báo**.
- Cố ý không làm gì (đi xuyên được, không validate lúc chạy…) thì ghi rõ là cố ý và vì sao.
- Sửa tool/lint/validator thì thêm selftest cho chính quy tắc mới.

## 5. Cách viết test

- Test ở **ranh giới công khai** của service/runtime, không test hàm private.
- Một bất biến mỗi test; tên test là câu khẳng định bất biến đó; thông điệp assert đọc được khi đỏ.
- **Assert đúng thuộc tính mình muốn nói.** "Chữ không bị cắt" = không clip, không trim, không dòng
  nào rộng hơn nhãn — đo được; không phải "đếm ≤ 2 dòng" (đã từng: mutation sống vì thế).
- Fake phải làm được điều chủ thật làm: nếu chủ thật phát signal từ bên trong lời gọi thì fake cũng
  phải gọi ngược lại được từ bên trong.
- Timing đo bằng frame/tick, không `await 2s rồi kiểm`. Không gian: đi bộ bằng phím thật, không
  teleport rồi kết luận về việc đi lại.
- Test mới **không được tự mang phụ thuộc mà nó cấm** (đã từng: test chống wall-clock lại assert
  một số đo wall-clock; quét `--fixed-fps` mới lộ).
- **Không nới test để qua.** Thiết kế đổi thì ghim lại *cùng bất biến*, đo trên thứ mới, và viết
  lý do ngay trong test.
- Tiêm lỗi (fault injection) cho đường thất bại hiếm: làm cho phụ thuộc thật từ chối/hỏng, đặt
  nhãn rõ là tiêm lỗi.

## 6. Git và CI

- Không commit thẳng `main`, không merge, không force-push, không `--no-verify`, không sửa lịch
  sử, trừ khi người dùng bảo. Merge là việc của người dùng; nhánh gate nối tiếp nhau
  (`gate-a → gate-b1 → gate-b2`) khi họ duyệt bằng lời mà chưa fast-forward.
- **Commit nguyên tử theo root cause**, mỗi commit buildable và xanh: fix + test của nó đi cùng;
  nới rộng test riêng; docs riêng; file sinh ra (bản dịch đã import, `.uid`) không bỏ sót.
- Stage **từng file theo tên**. Xem `git status --short` trước khi stage và sau khi commit.
- Message: conventional (`fix(scope): …`), dòng đầu nói bất biến mới bằng lời thường; thân nói
  trước đây hỏng thế nào (kèm con số), sửa ở đâu, vì sao không chọn cách khác. Kết thúc bằng dòng
  `Co-Authored-By` do phiên cung cấp.
- Sau push: `gh run watch` rồi đọc lại `headSha`, `conclusion`, `run_attempt`, số test trong log.
  Local xanh không thay CI; CI xanh không thay QA app thật; **re-run xanh không đóng lỗi nào**.

## 7. Báo cáo

- Mở đầu bằng kết quả: xong gì, SHA nào, CI nào. Rồi mới tới chi tiết.
- Mỗi khẳng định kèm bằng chứng (số đo, tên test, số run). Tách rõ: đã kiểm / kiểm một phần / chưa
  kiểm / bị chặn. Không dùng "chắc là", "có vẻ ổn".
- Nói cả cái làm sai trong lúc làm (tách nhầm nhánh, test tự viết bị lỗi) và đã xử lý thế nào.
- Ảnh/sheet: nói đã mở cái nào, chưa mở cái nào. Mutation: nói cái sống.
- Nợ còn lại: mỗi món có chủ và điều kiện đóng. Quyết định cần người dùng: hỏi một câu cụ thể.
- Viết cho người vừa quay lại sau khi làm việc khác: câu đủ ý, không ký hiệu tự chế.

## 8. Khi kẹt hoặc gặp chặn

- Lỗi công cụ, timeout, file khoá: chẩn đoán trước, thường không phải chặn thật — đợi, chia nhỏ,
  đổi cách gọi. Script treo không in gì: chạy lại có `timeout` và ghi log ra file.
- Chặn có chủ ý (file cấm đụng, quyền bị rút, guardrail): để nguyên, nói rõ, tìm đường khác.
- Thiếu công cụ bắt buộc (vd Blender cho việc cần Blender): dừng. Không thay bằng bằng chứng giả.
- Không biết con số: nói "không đo được vì …", không suy ra.

## 8b. Bốn luật giữ chất lượng (bắt buộc ở mọi task)

File này không tự bảo đảm điều gì: một AI có thể quên một luật chỉ nằm trong văn bản. Bốn luật
dưới đây là cách bù cho điều đó, và AI phải tự làm, không chờ nhắc.

1. **Báo cáo của AI không phải bằng chứng — kể cả báo cáo của chính mình.** Làm cho người duyệt
   tự kiểm được, và coi việc họ kiểm là bình thường:
   - Mỗi báo cáo cuối có đủ ba thứ để kiểm độc lập: **SHA đầy đủ + nhánh**, **số run CI và link**
     (đúng SHA đó, attempt thứ mấy), và **cách chạy thử** thứ vừa đổi (lệnh, đi đâu, bấm gì, sẽ
     thấy gì).
   - Tóm tắt diff theo file: đổi gì, vì sao. Không viết "đã sửa một số chỗ".
   - Khi nhận lại việc từ một AI khác hoặc từ phiên trước: đọc `git log`, `git diff`, log CI rồi
     mới tin; báo cáo cũ chỉ là chỉ dẫn nơi cần nhìn.
   - Không bao giờ viết "người dùng đã duyệt / đã chơi thử" nếu họ chưa nói thế trong phiên này.

2. **Việc dài phải có checkpoint dừng chờ duyệt.**
   - Brief có sẵn checkpoint: dừng đúng chỗ đó, gửi bằng chứng, **không tự đi tiếp**.
   - Brief không có mà việc lớn (nhiều hơn một root cause, đụng nhiều hệ thống, hoặc có thứ người
     dùng nhìn thấy): tự chia thành các gate, nói trước sẽ dừng ở đâu, và dừng ở đó.
   - Mỗi checkpoint là một trạng thái sạch: đã commit, đã push, CI xanh, `git status` sạch.
   - Quyết định thuộc về người dùng (đổi luật thiết kế, merge, xoá, phạm vi mới) thì hỏi tại
     checkpoint; không tự quyết rồi báo sau.

3. **Luật quan trọng phải thành thứ máy chặn được, ngay trong task tìm ra nó.**
   - Khi sửa một lỗi mà nguyên nhân là "ai đó đã quên một luật", hỏi: luật này chặn bằng máy
     được không? Theo thứ tự ưu tiên: **assert trong code** (hỏng là lộ ngay) → **test** → **lint**
     (có selftest) → **bước CI**. Làm cái đầu tiên khả thi, trong cùng task.
   - Chỉ khi không chặn bằng máy được mới ghi thành văn bản — và ghi kèm lý do không chặn được.
   - Ví dụ đã làm: "thân chỉ di chuyển trong fixed step" = assert + lint GD004; "shop phải có chủ
     đứng trong một map" = test nội dung; "không trang thừa trong Sổ Ký Sự" = test đo trên layout
     thật.
   - Không được tắt, nới hay bỏ qua một chốt chặn máy để cho qua. Chốt chặn sai thì sửa chốt chặn,
     có chứng minh và ghi lý do.

4. **Sai kiểu mới thì ghi lại đúng lỗi đó, kèm ví dụ, trước khi đóng task.**
   - Ghi vào `.kiro/steering/09-lessons-learned.md` (một mục `L-0xx`: chuyện gì đã xảy ra với con
     số thật, vì sao không ai bắt được, luật rút ra) — kể cả khi lỗi là của chính AI đang làm.
   - Nếu luật rút ra áp dụng cho mọi task (không riêng một hệ thống), **tự sửa file này luôn**,
     theo mục 8c. Không cần xin phép trước; phải báo lại sau.
   - Không ghi bài học chung chung ("cần cẩn thận hơn"). Một bài học phải nói được: lần sau làm
     gì khác đi, ở bước nào.

## 8c. AI tự sửa file này như thế nào

AI được tự cập nhật `CLAUDE.md` mà không cần hỏi. Đổi lại, mỗi lần sửa phải làm file **tốt hơn
cho người đọc kế tiếp**, không chỉ dài hơn. Các điều kiện dưới đây đều bắt buộc.

**Khi nào được sửa**

- Có một sự việc thật trong task đang làm: một lỗi kiểu mới, một bẫy môi trường mới, một lệnh /
  đường dẫn / con số trong file đã sai so với repo, hoặc một luật vừa được máy chặn (8b.3).
- Không sửa vì "nghĩ là sẽ hay hơn", vì sở thích diễn đạt, hay để hợp thức hoá cách mình vừa làm.

**Được làm**

- Thêm một luật mới, đúng mục của nó, **một đến ba dòng**, kèm ví dụ thật trong ngoặc (chuyện gì
  đã xảy ra, con số nếu có).
- Sửa cho đúng một sự thật đã lỗi thời (số test, số bước E2E, tên lệnh, tên file) — sau khi đã
  kiểm lại trên repo, không sửa theo trí nhớ.
- Gộp hai luật nói cùng một điều thành một, giữ ví dụ rõ hơn.
- Làm rõ một luật mà chính mình vừa hiểu sai — giữ nguyên ý, thêm chỗ đã gây hiểu sai.

**Không được làm**

- **Không nới, không xoá, không làm mờ một luật đang có** (bỏ một bước của quy trình, hạ một
  ngưỡng, đổi "phải" thành "nên", thêm ngoại lệ cho mình). Thấy một luật sai hoặc cản việc: giữ
  nguyên nó, làm theo nó, và nêu trong báo cáo để người dùng quyết.
- Không đổi các luật thuộc quyền người dùng: chính sách git (không merge / force-push / commit
  thẳng `main`), checkpoint dừng chờ duyệt, luật thiết kế (HUD, canon, phạm vi phase), mục 8b và
  chính mục 8c này.
- Không viết điều chưa kiểm thành luật. Quan sát chưa rõ nguyên nhân thì ghi đúng là quan sát,
  kèm "nguyên nhân chưa truy".
- Không để file mâu thuẫn với tài liệu chủ (mục 14). Tài liệu chủ thắng; nếu chính tài liệu chủ
  sai thì sửa tài liệu chủ trong repo (có commit), rồi mới đồng bộ file này.
- Không chép nội dung dài từ tài liệu chủ vào đây: file này chỉ giữ luật và con trỏ.
- Không stage, không commit file này: nó untracked và là của người dùng.

**Cách sửa cho tốt**

1. Đọc lại cả mục sắp sửa (và tìm trong toàn file) để chắc luật chưa có ở dạng khác. Có rồi thì
   bổ sung ví dụ vào chỗ đó, không thêm dòng mới.
2. Đặt đúng chỗ: luật chung vào Phần A; lệnh, bẫy máy, bất biến của dự án vào Phần B. Luật quy
   trình vào đúng bước của mục 2 mà nó thuộc về.
3. Viết để một AI chưa từng thấy sự việc vẫn làm đúng: **làm gì, ở bước nào, vì sao** — câu đủ ý,
   không viết tắt tự chế, không nhắc tới "lần trước" mà không kể lần trước là gì.
4. Ưu tiên máy chặn hơn chữ: nếu luật đã thành assert / test / lint thì dòng trong file chỉ cần
   nói nó tồn tại và ở đâu.
5. Giữ file gọn: Phần A không quá ~450 dòng (hiện ~400; trần do người dùng nâng). Sắp vượt thì gộp và rút ví dụ cũ trước khi thêm —
   không bao giờ bằng cách bỏ luật.
6. Sau khi sửa, đọc lại nguyên đoạn vừa sửa một lần như người mới: còn mâu thuẫn với dòng nào
   khác không, số mục và tham chiếu chéo (`mục 14`, `8b.3`) còn đúng không.

**Báo lại (bắt buộc)**

- Trong báo cáo cuối task có một mục riêng "Đã sửa CLAUDE.md": chép nguyên văn dòng thêm / sửa,
  mục nào, và sự việc đã sinh ra nó. Không sửa thì không cần mục này.
- Sửa mà không báo là vi phạm 8b.1: người dùng phải luôn biết file luật của họ đã đổi gì.

## 9. Tự hỏi trước khi nói "xong"

1. Cái gì đổi, vì sao, ai sở hữu state đó?
2. Đã thấy nó **đỏ** trước khi sửa chưa? Gỡ phần sửa ra thì test có đỏ lại không?
3. Lỗi cùng loại ở chỗ khác đã tìm và chặn chưa?
4. Người dùng thấy gì — đã chạy app thật, đã mở ảnh, đủ ngôn ngữ × kích thước chưa?
5. Lặp lại, lồng nhau, sai thời điểm, đường thất bại — còn đúng không?
6. Có tạo state trùng, global mới, nguồn sự thật thứ hai, file thừa không?
7. Diff đã tự đọc lại chưa? Docs đã ghi *vì sao* chưa? Lịch sử cũ còn nguyên không?
8. `git status` sạch chưa? CI xanh trên **đúng SHA** chưa?
9. Báo cáo có nói rõ cái chưa kiểm và cái còn nợ không?
10. Người duyệt có tự kiểm lại được không — có SHA, run CI, cách chạy thử chưa? (8b.1)
11. Đã dừng đúng checkpoint chưa, hay đang tự đi tiếp? (8b.2)
12. Luật vừa học đã thành assert / test / lint chưa? Lỗi kiểu mới đã ghi lại chưa? (8b.3, 8b.4)
13. Có sửa file này không? Nếu có: đúng điều kiện 8c chưa, và đã chép nguyên văn vào báo cáo chưa?

Trả lời không được câu nào → **chưa xong**.

---

# PHẦN B — RIÊNG DỰ ÁN AETHERIA

## 10. Bất biến kiến trúc

- Tầng: `data → domain → gameplay → presentation`. Dữ liệu mô tả, domain quyết định, presentation
  chỉ đọc. UI **không** mutate gameplay truth; file gameplay không viết `Color`.
- **Đúng 5 autoload** (EventBus, GameState, Localization, InputService, SceneRouter). Không thêm
  autoload, không `*Manager` toàn cục. Runtime theo phiên nằm dưới `Main/Systems`.
- **Một state, một chủ.** Một nguồn sự thật cho mỗi file sinh ra: hình và luật (sàn ↔ va chạm,
  sprite ↔ anchor, footprint ↔ body) sinh từ cùng một dữ liệu. Một feed cho mỗi dữ kiện hiển thị.
- UI đi qua `UIPalette → UITheme → screen`.
- **Thân chỉ được di chuyển trong fixed physics step**: `move_and_slide()` phải có
  `assert(MovementComponent.in_fixed_step(), …)` ngay trên nó (lint GD004 chặn). Test muốn bước
  thân thì `await fixed_step()` trước, và sau mỗi lần `await` process frame.
- Chủ sở hữu nhờ chủ khác làm việc giữa lúc ghi thì từ chối ghi lồng (`REFUSE_BUSY`): Story,
  Inventory.use, Equipment, Shop.transact, Dialogue, Quest, Reward.
- Rời map xảy ra tại `SceneRouter.transition_committing` (điểm không quay lại), không trước đó.
- Canon đóng: 5 cảnh giới, 4 nguyên tố (Hỏa/Thủy/Phong/Lôi), 5 họ vũ khí. Tên riêng theo
  `docs/CANON_LEDGER.md`. Nhân vật bắt đầu không tông môn; Xuất thân không quyết định tông môn,
  đường tu, vũ khí hay kết cục. Lore mới ghi `PROPOSAL — NOT FROZEN` cho tới khi được duyệt.
- Không làm phase tương lai trong việc hiện tại. Seam multiplayer/audio/save: chỉ giữ đường mở.

## 10b. Style GDScript của dự án (đầy đủ ở `.kiro/steering/04-coding-standards.md`)

- File và scene `snake_case`; `class_name` `PascalCase`; hàm, biến `snake_case`; thành viên private
  có gạch dưới đầu (`_state`) và **không file nào khác được chạm vào** (lint GD002); hằng và giá
  trị enum `UPPER_SNAKE_CASE`.
- Kiểu tĩnh ở chữ ký hàm và biến thành viên. `var x := <biểu thức trả Variant>` (`.call()`,
  `Dictionary.get()`) làm script **không compile** (lint GD001): khai `var x: Kiểu = …` hoặc ép
  kiểu. Mảng có kiểu không nhận mảng trơn: dựng biến `Array[int]` rồi mới gán.
- Dòng ≤ 100 ký tự (GD003). Thụt bằng tab như các file hiện có. UTF-8, LF.
- Đầu mỗi file: `extends`, `class_name`, rồi khối `##` nói file này **là gì, sở hữu gì, không làm
  gì**, và vì sao nó tồn tại. Hàm công khai có `##` nói hợp đồng của nó.
- Không số ma thuật, không dữ liệu gameplay trong script (để ở Resource `.tres`), không chuỗi hiển
  thị trong code (khoá bản địa hoá, có cả `en` lẫn `vi`).
- Ưu tiên `@export` + ghép thành phần hơn `get_node("../..")`; ưu tiên signal hơn với ngang cây.
- Runtime có `start_session` / `end_session` đối xứng: mọi thứ nối ở start phải gỡ ở end, và
  dựng vào biến cục bộ rồi mới commit (không để lại nửa phiên khi một kiểm tra hỏng).
- Presentation nhận **view** (DTO chỉ gồm khoá, icon, số) do `WorldRuntime` dựng từ các chủ sở hữu;
  không cầm tham chiếu tới runtime để tự hỏi.

## 11. Lệnh và gate

Godot: `~/Downloads/Godot_v4.7.2-stable_linux.x86_64` (gọi là `$G`).

| Gate | Lệnh |
|---|---|
| Lint (+selftest) | `python3 tools/gdscript_lint.py --selftest && python3 tools/gdscript_lint.py` (dòng ≤ 100 ký tự; GD001–GD004) |
| Nội dung sinh ra | `python3 tools/author_story_data.py --check` |
| Import | `$G --headless --path . --import` |
| Parse | `$G --headless --path . -s res://tools/parse_check.gd` |
| Boot | `$G --headless --path . --quit-after 2` |
| Suite | `$G --headless --path . -s res://tests/run_tests.gd [-- <chuỗi con đường dẫn> …]` |
| E2E (8 luồng, mỗi luồng một process) | `$G --headless --path . -s res://tests/e2e/run_{app,player,world,pet,npc,dialogue,quest,story}_flow.gd` |

- Luôn `grep -c 'SCRIPT ERROR'` trên log của suite và từng E2E.
- Lỗi phụ thuộc thời gian: chạy test với `--fixed-fps 5 / 60 / 100000` để ép process step.
- Thêm chuỗi vào `locale/aetheria.csv` thì chạy `--import` và commit cả hai file `.translation`.
- Validator pipeline art (style_check, verify_animates, determinism_check) báo lỗi → sửa art hoặc
  thuật toán; chỉ sửa phép đo khi chứng minh được phép đo sai, và ghi lý do.

## 12. Chất lượng người chơi nhìn thấy

- App thật, cửa sổ thật (không `--headless`):
  - `DISPLAY=:0 $G --path . --resolution 1280x720 --disable-vsync --max-fps 60 -s res://tools/capture_ui.gd -- <vi|en> <dir>`
  - `… -s res://tools/capture_motion.gd -- <dir> <scenario> [vi|en]` (vd `night_bite`, `dialogue`, `quest`, `cultivation`)
  - `… -s res://tools/playtest_flow.gd -- <vi|en> <dir>` (phím thật, 39 bước, exit code là gate)
  - `… --max-fps 0 -s res://tools/measure_ambience_frame_time.gd -- <report.md>`
- Ma trận: vi và en × 1280×720 và 1280×800. Ảnh và log để ở scratch hoặc `user://`, không commit.
- Phóng to 5–10× để soi sprite, rồi xem lại ở 1×.
- Phản hồi cho hành động trực tiếp: ≤ 2 frame và ≤ 100 ms. Không hạ ngưỡng để PASS.
- Vật có khối hình + vai trò gameplay phải có body, tách khỏi vùng tương tác; cố ý đi xuyên thì
  ghi `INTANGIBLE_BY_DESIGN`. Mọi vật cần tới phải có chỗ đứng đi bộ tới được trong tầm của nó.
- HUD: ≤ 15% màn hình, vùng giữa 50%×50% để trống, không minimap / thanh MP / chat / 4 hộp lớn —
  cho tới khi chủ dự án đổi luật. Panel modal (túi đồ) được rộng hơn, bằng một hằng có tên.
- Nhân vật hiện ra là **hình** ở nơi nói về họ (`CharacterCard`: sprite của chính game, tỉ lệ
  nguyên, ô trang bị, chỉ số). Tên xuống dòng, không bao giờ bị cắt; số chưa có là "—", không là 0.
- Không "làm đẹp" bằng thêm glow, particle, vàng, bão hoà, hoạ tiết, panel.
- Ảnh game khác chỉ để phân tích nguyên lý: không copy, không commit.

## 13. Art pipeline và bẫy môi trường

**Pipeline** (`tools/aetheria_art_pipeline/`, xem README ở đó):

- Một Visual DNA: `style/aetheria_style.yaml`. Mở rộng pipeline hiện có; diễn viên / đạo cụ / icon
  mới = **dữ liệu thiết kế mới**, không phải code renderer mới.
- Blender (MCP `blender-pro`) là công cụ build, không bao giờ là phụ thuộc runtime.
- `docs/design_refs/` gitignored; canon thắng moodboard (đầu ≈ 1/3 ở 32×48, top-down).
- Chỉ ship thứ game nạp. Trung gian ở `work/`. PNG ghi qua `pixel/pngout.py` (lossless). Ghi
  provenance vào `docs/ASSET_LICENSES.md`. Không sửa tay PNG đã sinh.

**Bẫy máy này:**

- Pipeline art cần `/usr/bin/python3` (PIL + PyYAML); `python3` trên PATH có thể là venv thiếu PIL.
- Màn hình khoá: cửa sổ thật chạy ~1 fps nếu bật vsync → luôn `--disable-vsync --max-fps 60`.
  Chạy capture ở nền, **từng cái một**; không chạy Godot khác trong lúc đang đo thời gian.
- Không `pkill -f <tên script>` (khớp cả shell đang gọi).
- `blender-pro execute_code` trả về sau 300 s dù Blender còn render: render 1–2 actor mỗi lần,
  poll file; sau khi Blender khởi động lại phải thêm lại `model/` và `blender/` vào `sys.path`.
- RAM chật: không chạy Blender render và ma trận capture cùng lúc.
- Scratchpad `/tmp` có thể bị xoá; thứ cần giữ thì đưa vào repo (như bước 21c của playtest).
- Checkout có thể bị đổi giữa hai lệnh (IDE / người dùng): luôn tách nhánh theo SHA.
- Ngôn ngữ phải đặt **sau** khi `main` đã boot: `Main._boot` (`src/bootstrap/main.gd`) áp ngôn ngữ
  đã lưu trong `SettingsStore`, nên script dò đặt `vi` trước khi nạp `main` vẫn ra ảnh tiếng Anh
  nếu lượt chạy trước là `en`. Dùng tool có tham số ngôn ngữ (`capture_ui`, `playtest_flow`), hoặc
  đặt sau boot rồi kiểm chữ trong ảnh.
- Bước chụp / dò nào đổi state (mặc đồ, dùng vật phẩm) thì trả state về như cũ; danh sách khung
  hình đổi tên / đổi số là một phát hiện. (Đã từng: một khung chụp để nguyên thanh kiếm đang mang
  → Sổ Ký Sự thêm một trang → 11 khung sau lệch số, hết so được với baseline.)

## 14. Tài liệu chủ (đọc phần liên quan trước khi sửa vùng đó)

| Vùng | Tài liệu |
|---|---|
| Quy trình phase, review AI, CI | `docs/PHASE_EXECUTION_PROTOCOL.md`, `.kiro/steering/08-ai-review-protocol.md`, `10-ci-failure-protocol.md`, `09-lessons-learned.md` (L-0xx: mỗi bài học là một lỗi thật) |
| Kiến trúc, phụ thuộc | `.kiro/steering/03-architecture.md`, `docs/ARCHITECTURE.md`, `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md`, `docs/SYSTEM_DEPENDENCY_MATRIX.md` |
| Canon, thế giới, cốt truyện | `docs/CANON_LEDGER.md`, `docs/WORLD_BIBLE.md`, `docs/GAME_DESIGN_FREEZE.md`, `docs/NARRATIVE_MASTER_PLAN.md`, `docs/NARRATIVE_DIRECTION.md` |
| Hình ảnh, chuyển động | `docs/CHARACTER_ART_BIBLE.md`, `docs/MOTION_DESIGN_CONTRACT.md`, `docs/XIANXIA_IDENTITY_CONTRACT.md`, `docs/AETHERIA_ART_PIPELINE.md`, `.kiro/steering/06-art-assets.md` |
| UI, bản địa hoá | `docs/UI_UX_BIBLE.md`, `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md`, `.kiro/steering/07-localization.md` |
| Code, hiệu năng, test | `.kiro/steering/04-coding-standards.md`, `05-performance-testing.md`, `docs/TEST_PLAN.md`, `docs/PERFORMANCE.md` |
| Quyết định, tiến độ, nợ | `docs/DECISIONS.md`, `docs/ROADMAP.md`, `docs/handoff/` (bảng nợ: mỗi món có chủ và điều kiện đóng) |
