import type { Player } from '../types/game';

type DistortionAction = 'remove_option' | 'swap_category' | 'force_blind' | 'inject_fake_option';

interface TruthDistortionPanelProps {
  myCharges: number;
  myPlayerId?: string;
  players: Player[];
  pendingDistortion: DistortionAction | null;
  distortionTarget: string;
  distortionLocked: boolean;
  distortionToast: string | null;
  fakeLockConfirmed: boolean;
  fakeOptionText: string;
  fakePreview: { category_label?: string; text?: string } | null;
  readySent: boolean;
  readySubmitting?: boolean;
  readyProgress: { acked: number; total: number } | null;
  doneLabel: string;
  doneLabelWithPower?: string;
  usedPowers?: Record<string, number>;
  onToggleDistortion: (action: DistortionAction) => void;
  onSetDistortionTarget: (id: string) => void;
  onSetFakeOptionText: (text: string) => void;
  onConfirmFakeLock: () => void;
  onDone: () => void;
}

const POWER_LIMITS: Record<string, number> = {
  remove_option: 1,
  swap_category: 2,
  force_blind: 1,
  inject_fake_option: 1,
};

export function TruthDistortionPanel({
  myCharges,
  myPlayerId,
  players,
  pendingDistortion,
  distortionTarget,
  distortionLocked,
  distortionToast,
  fakeLockConfirmed,
  fakeOptionText,
  fakePreview,
  readySent,
  readySubmitting = false,
  readyProgress,
  doneLabel,
  doneLabelWithPower = 'Xác nhận sức mạnh & sẵn sàng',
  usedPowers = {},
  onToggleDistortion,
  onSetDistortionTarget,
  onSetFakeOptionText,
  onConfirmFakeLock,
  onDone,
}: TruthDistortionPanelProps) {
  const isUsed = (action: string) => (usedPowers[action] ?? 0) >= (POWER_LIMITS[action] ?? 1);

  const renderPowerButton = (
    action: DistortionAction,
    label: string,
    cost: number,
  ) => {
    const used = isUsed(action);
    const disabled = used || myCharges < cost || distortionLocked;
    return (
      <button
        type="button"
        onClick={() => !used && onToggleDistortion(action)}
        disabled={disabled}
        className={`py-3 rounded-xl border-2 font-bold transition-all relative ${
          used
            ? 'opacity-40 cursor-not-allowed bg-gray-100 border-gray-300 text-gray-500'
            : disabled
              ? 'opacity-50'
              : pendingDistortion === action
                ? 'bg-purple-600 text-white border-purple-600'
                : ''
        }`}
      >
        {used ? (
          <span className="text-xs">✅ Đã sử dụng</span>
        ) : (
          `${label} (${cost})`
        )}
      </button>
    );
  };

  return (
    <div className="mt-8 p-6 rounded-xl border-2 border-purple-200 bg-white">
      <div className="flex items-center justify-between mb-4">
        <p className="text-xl font-black text-purple-700">Sức Mạnh Bóp Méo</p>
        <p className="text-xl font-black text-pink-700">{myCharges} điểm năng lượng</p>
      </div>
      {distortionToast && (
        <div className="mb-4 p-3 rounded-lg border border-purple-200 bg-purple-50 text-purple-800 font-semibold">
          {distortionToast}
        </div>
      )}
      <div className="grid grid-cols-2 gap-3">
        {renderPowerButton('remove_option', 'Xóa đáp án', 2)}
        {renderPowerButton('swap_category', 'Đổi chủ đề', 2)}
        {renderPowerButton('force_blind', 'Xáo trộn', 3)}
        {renderPowerButton('inject_fake_option', 'Chèn đáp án giả', 4)}
      </div>

      {pendingDistortion === 'force_blind' && (
        <div className="mt-4 p-3 rounded-xl border border-purple-200 bg-purple-50/70">
          <p className="text-sm font-bold text-purple-800 mb-1">Mục tiêu xáo trộn (tùy chọn)</p>
          <p className="text-xs text-purple-700 mb-2">
            Để trống để xáo trộn đáp án của tất cả người chơi khác. Hoặc chọn một người chơi.
          </p>
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => onSetDistortionTarget('')}
              className={`rounded-lg px-3 py-2 border-2 text-sm font-bold ${
                distortionTarget === ''
                  ? 'bg-purple-600 text-white border-purple-600'
                  : 'bg-white text-purple-800 border-purple-200'
              }`}
            >
              Tất cả người khác
            </button>
            {players
              .slice()
              .sort((a, b) => a.nickname.localeCompare(b.nickname))
              .map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => onSetDistortionTarget(p.id)}
                  className={`rounded-lg px-3 py-2 border-2 text-sm font-bold ${
                    distortionTarget === p.id
                      ? 'bg-purple-600 text-white border-purple-600'
                      : 'bg-white text-purple-800 border-purple-200'
                  }`}
                >
                  {p.nickname}
                </button>
              ))}
          </div>
        </div>
      )}

      {pendingDistortion === 'remove_option' && (
        <div className="mt-4 p-3 rounded-xl border border-purple-200 bg-purple-50/70">
          <p className="text-sm font-bold text-purple-800 mb-2">Chọn người chơi mục tiêu (bắt buộc)</p>
          <div className="grid grid-cols-2 gap-2">
            {players
              .slice()
              .sort((a, b) => a.nickname.localeCompare(b.nickname))
              .map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => onSetDistortionTarget(p.id)}
                  className={`rounded-lg px-3 py-2 border-2 text-sm font-bold ${
                    distortionTarget === p.id
                      ? 'bg-purple-600 text-white border-purple-600'
                      : 'bg-white text-purple-800 border-purple-200'
                  }`}
                >
                  {p.nickname}
                </button>
              ))}
          </div>
        </div>
      )}

      {pendingDistortion === 'inject_fake_option' && (
        <div className="mt-4 p-3 rounded-xl border border-purple-200 bg-purple-50/70">
          <p className="text-sm font-bold text-purple-800 mb-2">Viết đáp án giả</p>
          {!fakeLockConfirmed ? (
            <div className="text-xs text-purple-700 mb-3 space-y-1">
              <p>
                Nhập một đáp án sai nhưng có vẻ đúng. Nếu có người chọn đáp án giả, bạn
                sẽ được thưởng điểm!
              </p>
              <button
                type="button"
                onClick={onConfirmFakeLock}
                className="mt-1 px-4 py-2 rounded-xl border-2 border-purple-600 bg-purple-600 text-white font-bold"
              >
                Đã hiểu, tiếp tục
              </button>
            </div>
          ) : (
            <div>
              {fakePreview && (
                <div className="mb-2 text-xs text-purple-600">
                  <span className="font-bold">{fakePreview.category_label}</span>:{' '}
                  {fakePreview.text}
                </div>
              )}
              <input
                value={fakeOptionText}
                onChange={(e) => onSetFakeOptionText(e.target.value)}
                maxLength={60}
                placeholder="Đáp án giả (VD: 5 hoặc một đáp án sai có vẻ đúng)"
                className="w-full rounded-xl border-2 border-purple-200 px-3 py-3 font-semibold"
              />
            </div>
          )}
        </div>
      )}

      <div className="mt-6 p-4 rounded-xl border border-purple-200 bg-purple-50/90 relative z-20">
        {readyProgress ? (
          <p className="text-center font-bold text-purple-800 mb-3">
            Sẵn sàng: {readyProgress.acked}/{readyProgress.total}
          </p>
        ) : null}
        <button
          type="button"
          disabled={readySent || readySubmitting}
          onPointerUp={(e) => {
            e.preventDefault();
            if (readySent || readySubmitting) return;
            onDone();
          }}
          className={`w-full py-4 rounded-xl font-black text-lg bg-gradient-to-r from-pink-500 to-purple-600 text-white shadow-lg touch-manipulation cursor-pointer relative z-30 transition-all ${
            readySent || readySubmitting
              ? 'opacity-60'
              : 'hover:brightness-105 active:scale-95 active:opacity-90'
          }`}
        >
          {readySubmitting
            ? 'Đang gửi…'
            : readySent
              ? 'Đang chờ người chơi khác…'
              : pendingDistortion && !distortionLocked
                ? doneLabelWithPower
                : doneLabel}
        </button>
        <p className="text-xs text-gray-600 mt-2 text-center">
          Nhấn Xong bất cứ lúc nào. Nếu bạn đã chọn sức mạnh, Xong sẽ xác nhận và đánh dấu bạn sẵn sàng.
        </p>
      </div>
    </div>
  );
}
