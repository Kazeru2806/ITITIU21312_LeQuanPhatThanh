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
                    <h1 className="text-2xl font-black text-purple-800">Something went wrong</h1>
                    <p className="text-gray-700 max-w-md font-semibold">{this.state.error.message}</p>
                    <p className="text-sm text-gray-500 max-w-md">
                        Try a hard refresh. If this persists, the player app may need a new deploy on Vercel.
                    </p>
                    <button
                        type="button"
                        onClick={() => window.location.assign('/')}
                        className="px-6 py-3 rounded-xl bg-purple-600 text-white font-bold"
                    >
                        Back to join screen
                    </button>
                </div>
            );
        }
        return this.props.children;
    }
}
