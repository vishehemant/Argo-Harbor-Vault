/**
 * Tetris Game - Complete implementation with ghost piece, scoring, and pause
 */

const COLS = 10;
const ROWS = 20;
const BLOCK_SIZE = 24;
const PIECE_COLORS = [
    null,
    '#00f5ff',  // I - Cyan
    '#ff9500',  // J - Orange
    '#0066ff',  // L - Blue
    '#ffff00',  // O - Yellow
    '#00ff88',  // S - Green
    '#aa00ff',  // T - Purple
    '#ff0044',  // Z - Red
];

// Immutable piece definitions - each piece has 4 rotation states (index 0-3)
const PIECE_SHAPES = {
    1: [  // I
        [[0, 0, 0, 0], [1, 1, 1, 1], [0, 0, 0, 0], [0, 0, 0, 0]],
        [[0, 1, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0]],
        [[0, 0, 0, 0], [0, 0, 0, 0], [1, 1, 1, 1], [0, 0, 0, 0]],
        [[0, 0, 1, 0], [0, 0, 1, 0], [0, 0, 1, 0], [0, 0, 1, 0]],
    ],
    2: [  // J
        [[2, 0, 0], [2, 2, 2], [0, 0, 0]],
        [[0, 2, 2], [0, 2, 0], [0, 2, 0]],
        [[0, 0, 0], [2, 2, 2], [0, 0, 2]],
        [[0, 2, 0], [0, 2, 0], [2, 2, 0]],
    ],
    3: [  // L
        [[0, 0, 3], [3, 3, 3], [0, 0, 0]],
        [[0, 3, 0], [0, 3, 0], [0, 3, 3]],
        [[0, 0, 0], [3, 3, 3], [3, 0, 0]],
        [[3, 3, 0], [0, 3, 0], [0, 3, 0]],
    ],
    4: [  // O - same in all rotations
        [[4, 4], [4, 4]], [[4, 4], [4, 4]], [[4, 4], [4, 4]], [[4, 4], [4, 4]],
    ],
    5: [  // S
        [[0, 5, 5], [5, 5, 0], [0, 0, 0]],
        [[0, 5, 0], [0, 5, 5], [0, 0, 5]],
        [[0, 0, 0], [0, 5, 5], [5, 5, 0]],
        [[5, 0, 0], [5, 5, 0], [0, 5, 0]],
    ],
    6: [  // T
        [[0, 6, 0], [6, 6, 6], [0, 0, 0]],
        [[0, 6, 0], [0, 6, 6], [0, 6, 0]],
        [[0, 0, 0], [6, 6, 6], [0, 6, 0]],
        [[0, 6, 0], [6, 6, 0], [0, 6, 0]],
    ],
    7: [  // Z
        [[7, 7, 0], [0, 7, 7], [0, 0, 0]],
        [[0, 0, 7], [0, 7, 7], [0, 7, 0]],
        [[0, 0, 0], [7, 7, 0], [0, 7, 7]],
        [[0, 7, 0], [7, 7, 0], [7, 0, 0]],
    ],
};

function getPieceShape(pieceId, rotation = 0) {
    return PIECE_SHAPES[pieceId][rotation % PIECE_SHAPES[pieceId].length];
}

const LINE_SCORES = [0, 100, 300, 500, 800];

let canvas, ctx, nextCanvas, nextCtx;
let board, currentPiece, nextPiece, pieceX, pieceY, currentPieceRotation;
let score = 0, level = 1, lines = 0;
let gameOver = false, paused = false;
let lastDrop = 0;
let dropInterval = 1000;

function init() {
    canvas = document.getElementById('gameCanvas');
    ctx = canvas.getContext('2d');
    nextCanvas = document.getElementById('nextCanvas');
    nextCtx = nextCanvas.getContext('2d');

    const boardWidth = COLS * BLOCK_SIZE;
    const boardHeight = ROWS * BLOCK_SIZE;
    canvas.width = boardWidth;
    canvas.height = boardHeight;

    board = createBoard();
    bindEvents();
    fetchApiInfo();
    resetGame();
    requestAnimationFrame(gameLoop);
}

function createBoard() {
    return Array.from({ length: ROWS }, () => Array(COLS).fill(0));
}

function getRandomPiece() {
    return Math.floor(Math.random() * 7) + 1;
}

function resetGame() {
    board = createBoard();
    score = 0;
    level = 1;
    lines = 0;
    gameOver = false;
    paused = false;
    dropInterval = 1000;
    nextPiece = getRandomPiece();
    spawnPiece();
    updateStats();
    document.getElementById('pauseOverlay').classList.remove('active');
    document.getElementById('gameOverOverlay').classList.remove('active');
}

function spawnPiece() {
    currentPiece = nextPiece;
    currentPieceRotation = 0;
    nextPiece = getRandomPiece();
    const shape = getPieceShape(currentPiece, 0);
    pieceX = Math.floor(COLS / 2) - Math.floor(shape[0].length / 2);
    pieceY = 0;

    if (collides(pieceX, pieceY, shape)) {
        gameOver = true;
        document.getElementById('finalScore').textContent = score;
        document.getElementById('gameOverOverlay').classList.add('active');
    }
}

function collides(x, y, piece) {
    const shape = piece ?? getPieceShape(currentPiece, currentPieceRotation);
    for (let row = 0; row < shape.length; row++) {
        for (let col = 0; col < shape[row].length; col++) {
            if (shape[row][col]) {
                const newX = x + col;
                const newY = y + row;
                if (newX < 0 || newX >= COLS || newY >= ROWS) return true;
                if (newY >= 0 && board[newY][newX]) return true;
            }
        }
    }
    return false;
}

function mergePiece() {
    const shape = getPieceShape(currentPiece, currentPieceRotation);
    for (let row = 0; row < shape.length; row++) {
        for (let col = 0; col < shape[row].length; col++) {
            if (shape[row][col]) {
                const boardY = pieceY + row;
                const boardX = pieceX + col;
                if (boardY >= 0) {
                    board[boardY][boardX] = currentPiece;
                }
            }
        }
    }
}

function clearLines() {
    let cleared = 0;
    for (let row = ROWS - 1; row >= 0; row--) {
        if (board[row].every(cell => cell !== 0)) {
            board.splice(row, 1);
            board.unshift(Array(COLS).fill(0));
            cleared++;
            row++;
        }
    }
    if (cleared > 0) {
        score += LINE_SCORES[cleared] * level;
        lines += cleared;
        level = Math.floor(lines / 10) + 1;
        dropInterval = Math.max(100, 1000 - (level - 1) * 100);
    }
}

function getGhostY() {
    let ghostY = pieceY;
    const shape = getPieceShape(currentPiece, currentPieceRotation);
    while (!collides(pieceX, ghostY + 1, shape)) {
        ghostY++;
    }
    return ghostY;
}

function rotatePiece() {
    if (gameOver || paused) return;
    const rotations = PIECE_SHAPES[currentPiece];
    const nextRotation = (currentPieceRotation + 1) % rotations.length;
    const rotated = rotations[nextRotation];
    if (!collides(pieceX, pieceY, rotated)) {
        currentPieceRotation = nextRotation;
    }
}

function movePiece(dx) {
    if (gameOver || paused) return;
    if (!collides(pieceX + dx, pieceY, getPieceShape(currentPiece, currentPieceRotation))) {
        pieceX += dx;
    }
}

function softDrop() {
    if (gameOver || paused) return;
    if (!collides(pieceX, pieceY + 1, getPieceShape(currentPiece, currentPieceRotation))) {
        pieceY++;
        score += 1;
    }
}

function hardDrop() {
    if (gameOver || paused) return;
    const ghostY = getGhostY();
    score += (ghostY - pieceY) * 2;
    pieceY = ghostY;
    mergePiece();
    clearLines();
    spawnPiece();
}

function drawBlock(ctx, x, y, color, isGhost = false) {
    const padding = 1;
    const size = BLOCK_SIZE - padding;

    if (isGhost) {
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.globalAlpha = 0.35;
        ctx.strokeRect(x * BLOCK_SIZE + padding, y * BLOCK_SIZE + padding, size, size);
        ctx.globalAlpha = 1;
        return;
    }

    ctx.fillStyle = color;
    ctx.fillRect(x * BLOCK_SIZE + padding, y * BLOCK_SIZE + padding, size, size);

    ctx.strokeStyle = 'rgba(255,255,255,0.3)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x * BLOCK_SIZE + padding, y * BLOCK_SIZE + padding, size, size);
}

function drawBoard() {
    ctx.fillStyle = '#050518';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    for (let row = 0; row < ROWS; row++) {
        for (let col = 0; col < COLS; col++) {
            if (board[row][col]) {
                drawBlock(ctx, col, row, PIECE_COLORS[board[row][col]]);
            }
        }
    }

    if (!gameOver && currentPiece) {
        const ghostY = getGhostY();
        const shape = getPieceShape(currentPiece, currentPieceRotation);
        for (let row = 0; row < shape.length; row++) {
            for (let col = 0; col < shape[row].length; col++) {
                if (shape[row][col]) {
                    drawBlock(ctx, pieceX + col, ghostY + row, PIECE_COLORS[currentPiece], true);
                }
            }
        }

        for (let row = 0; row < shape.length; row++) {
            for (let col = 0; col < shape[row].length; col++) {
                if (shape[row][col]) {
                    drawBlock(ctx, pieceX + col, pieceY + row, PIECE_COLORS[currentPiece]);
                }
            }
        }
    }
}

function drawNextPiece() {
    nextCtx.fillStyle = '#121240';
    nextCtx.fillRect(0, 0, nextCanvas.width, nextCanvas.height);

    const shape = getPieceShape(nextPiece, 0);
    const blockSize = 16;
    const padding = 1;
    const offsetX = (nextCanvas.width - shape[0].length * (blockSize + padding)) / 2;
    const offsetY = (nextCanvas.height - shape.length * (blockSize + padding)) / 2;

    for (let row = 0; row < shape.length; row++) {
        for (let col = 0; col < shape[row].length; col++) {
            if (shape[row][col]) {
                const px = offsetX + col * (blockSize + padding);
                const py = offsetY + row * (blockSize + padding);
                nextCtx.fillStyle = PIECE_COLORS[nextPiece];
                nextCtx.fillRect(px, py, blockSize, blockSize);
                nextCtx.strokeStyle = 'rgba(255,255,255,0.3)';
                nextCtx.lineWidth = 1;
                nextCtx.strokeRect(px, py, blockSize, blockSize);
            }
        }
    }
}

function updateStats() {
    document.getElementById('score').textContent = score;
    document.getElementById('level').textContent = level;
    document.getElementById('lines').textContent = lines;
}

function gameLoop(timestamp) {
    if (!gameOver && !paused && currentPiece) {
        if (timestamp - lastDrop > dropInterval) {
            if (collides(pieceX, pieceY + 1, getPieceShape(currentPiece, currentPieceRotation))) {
                mergePiece();
                clearLines();
                spawnPiece();
            } else {
                pieceY++;
            }
            lastDrop = timestamp;
        }
    }

    drawBoard();
    drawNextPiece();
    updateStats();
    requestAnimationFrame(gameLoop);
}

function bindEvents() {
    document.addEventListener('keydown', (e) => {
        if (gameOver && e.key !== 'Enter' && e.key !== ' ') return;

        switch (e.key) {
            case 'ArrowLeft':
                e.preventDefault();
                movePiece(-1);
                break;
            case 'ArrowRight':
                e.preventDefault();
                movePiece(1);
                break;
            case 'ArrowDown':
                e.preventDefault();
                softDrop();
                break;
            case 'ArrowUp':
                e.preventDefault();
                rotatePiece();
                break;
            case ' ':
                e.preventDefault();
                if (gameOver) {
                    resetGame();
                } else {
                    hardDrop();
                }
                break;
            case 'p':
            case 'P':
                e.preventDefault();
                if (!gameOver && currentPiece) {
                    paused = !paused;
                    document.getElementById('pauseOverlay').classList.toggle('active', paused);
                }
                break;
        }
    });

    document.getElementById('restartBtn').addEventListener('click', () => {
        resetGame();
    });
}

function fetchApiInfo() {
    fetch('/api/info')
        .then(res => res.json())
        .then(data => {
            document.getElementById('version').textContent = `v${data.version || '1.0.0'}`;
            document.getElementById('hostname').textContent = data.hostname || '-';

            const envBadge = document.getElementById('envBadge');
            const env = (data.environment || 'dev').toLowerCase();
            envBadge.textContent = env;
            envBadge.className = 'env-badge ' + (['dev', 'uat', 'prod'].includes(env) ? env : 'unknown');
        })
        .catch(() => {
            document.getElementById('version').textContent = 'v1.0.0';
            document.getElementById('envBadge').textContent = 'dev';
            document.getElementById('envBadge').className = 'env-badge dev';
        });
}

init();
