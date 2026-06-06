import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
    children: ReactNode;
}

interface State {
    error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
    state: State = { error: null };

    static getDerivedStateFromError(error: Error): State {
        return { error };
    }

    componentDidCatch(error: Error, info: ErrorInfo) {
        console.error('Player app crashed:', error, info.componentStack);
    }

    render() {
        if (this.state.error) {
            return (
                <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-b from-purple-50 to-pink-50 p-6 gap-4 text-center">
                    <h1 className="text-2xl font-black text-purple-800">Đã xảy ra lỗi</h1>
                    <p className="text-gray-700 max-w-md font-semibold">{this.state.error.message}</p>
                    <p className="text-sm text-gray-500 max-w-md">
                        Hãy tải lại trang. Nếu lỗi vẫn tiếp tục, ứng dụng có thể cần được cập nhật.
                    </p>
                    <button
                        type="button"
                        onClick={() => window.location.assign('/')}
                        className="px-6 py-3 rounded-xl bg-purple-600 text-white font-bold"
                    >
                        Quay lại màn hình tham gia
                    </button>
                </div>
            );
        }
        return this.props.children;
    }
}
