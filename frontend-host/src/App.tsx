import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { LandingPage } from './pages/LandingPage';
import { LobbyPage } from './pages/LobbyPage';
import { GameDisplayPage } from './pages/GameDisplayPage';
import { ResultsPage } from './pages/ResultsPage';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/lobby" element={<LobbyPage />} />
        <Route path="/game" element={<GameDisplayPage />} />
        <Route path="/results" element={<ResultsPage />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
