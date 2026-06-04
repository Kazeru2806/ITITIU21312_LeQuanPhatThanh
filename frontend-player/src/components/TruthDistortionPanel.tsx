import type { Player } from '../types/game';

type DistortionAction = 'remove_option' | 'swap_category' | 'force_blind' | 'inject_fake_option';

interface TruthDistortionPanelProps {
  myCharges: number;
  players: Player[];
  pendingDistortion: DistortionAction | null;
  distortionTarget: string;
  distortionLocked: boolean;
  distortionToast: string | null;
  fakeLockConfirmed: boolean;
  fakeOptionText: string;
  fakePreview: { category_label?: string; text?: string } | null;
  readySent: boolean;
  readyProgress: { acked: number; total: number } | null;
  doneLabel: string;
  doneLabelWithPower?: string;
  onToggleDistortion: (action: DistortionAction) => void;
  onSetDistortionTarget: (id: string) => void;
  onSetFakeOptionText: (text: string) => void;
  onConfirmFakeLock: () => void;
  onDone: () => void;
}

export function TruthDistortionPanel({
  myCharges,
  players,
  pendingDistortion,
  distortionTarget,
  distortionLocked,
  distortionToast,
  fakeLockConfirmed,
  fakeOptionText,
  fakePreview,
  readySent,
  readyProgress,
  doneLabel,
  doneLabelWithPower = 'Confirm power & ready',
  onToggleDistortion,
  onSetDistortionTarget,
  onSetFakeOptionText,
  onConfirmFakeLock,
  onDone,
}: TruthDistortionPanelProps) {
  return (
    <div className="mt-8 p-6 rounded-xl border-2 border-purple-200 bg-white">
      <div className="flex items-center justify-between mb-4">
        <p className="text-xl font-black text-purple-700">Distortion Power</p>
        <p className="text-xl font-black text-pink-700">{myCharges} charges</p>
      </div>
      {distortionToast && (
        <div className="mb-4 p-3 rounded-lg border border-purple-200 bg-purple-50 text-purple-800 font-semibold">
          {distortionToast}
        </div>
      )}
      <div className="grid grid-cols-2 gap-3">
        <button
          type="button"
          onClick={() => onToggleDistortion('remove_option')}
          disabled={myCharges < 2 || distortionLocked}
          className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${
            pendingDistortion === 'remove_option' ? 'bg-purple-600 text-white border-purple-600' : ''
          }`}
        >
          Remove option (2)
        </button>
        <button
          type="button"
          onClick={() => onToggleDistortion('swap_category')}
          disabled={myCharges < 2 || distortionLocked}
          className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${
            pendingDistortion === 'swap_category' ? 'bg-purple-600 text-white border-purple-600' : ''
          }`}
        >
          Swap category (2)
        </button>
        <button
          type="button"
          onClick={() => onToggleDistortion('force_blind')}
          disabled={myCharges < 3 || distortionLocked}
          className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${
            pendingDistortion === 'force_blind' ? 'bg-purple-600 text-white border-purple-600' : ''
          }`}
        >
          Shuffle answers (3)
        </button>
        <button
          type="button"
          onClick={() => onToggleDistortion('inject_fake_option')}
          disabled={myCharges < 4 || distortionLocked}
          className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${
            pendingDistortion === 'inject_fake_option' ? 'bg-purple-600 text-white border-purple-600' : ''
          }`}
        >
          Inject fake option (4)
        </button>
      </div>

      {pendingDistortion === 'remove_option' && (
        <div className="mt-4 p-3 rounded-xl border border-purple-200 bg-purple-50/70">
          <p className="text-sm font-bold text-purple-800 mb-2">Choose target player</p>
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
          {!fakeLockConfirmed ? (
            <div className="space-y-3">
              <p className="text-sm text-purple-800 font-semibold">
                Confirm lock? This reveals the next question preview.
              </p>
              <button
                type="button"
                onClick={onConfirmFakeLock}
                className="w-full rounded-xl px-4 py-3 font-black bg-gradient-to-r from-purple-600 to-pink-500 text-white"
              >
                Yes, lock it
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              {fakePreview && (
                <div className="rounded-lg border border-purple-200 bg-white p-3">
                  <p className="text-xs font-bold text-purple-700">Preview</p>
                  <p className="font-black text-purple-900">{fakePreview.category_label}</p>
                  <p className="text-sm text-gray-700">{fakePreview.text}</p>
                </div>
              )}
              <input
                value={fakeOptionText}
                onChange={(e) => onSetFakeOptionText(e.target.value)}
                maxLength={60}
                placeholder="Fake answer text"
                className="w-full rounded-xl border-2 border-purple-200 px-3 py-3 font-semibold"
              />
            </div>
          )}
        </div>
      )}

      <div className="mt-6 p-4 rounded-xl border border-purple-200 bg-purple-50/90 relative z-20">
        {readyProgress ? (
          <p className="text-center font-bold text-purple-800 mb-3">
            Ready: {readyProgress.acked}/{readyProgress.total}
          </p>
        ) : null}
        <button
          type="button"
          disabled={readySent}
          onClick={() => {
            if (readySent) return;
            onDone();
          }}
          className="w-full py-4 rounded-xl font-black text-lg bg-gradient-to-r from-pink-500 to-purple-600 text-white disabled:opacity-60 shadow-lg touch-manipulation cursor-pointer"
        >
          {readySent
            ? 'Waiting for other players…'
            : pendingDistortion && !distortionLocked
              ? doneLabelWithPower
              : doneLabel}
        </button>
        <p className="text-xs text-gray-600 mt-2 text-center">
          Tap Done anytime. If you picked a power, Done confirms it and marks you ready. Everyone ready skips the wait.
        </p>
      </div>
    </div>
  );
}
