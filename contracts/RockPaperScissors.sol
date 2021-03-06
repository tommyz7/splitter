pragma solidity ^0.4.18;

import './Ownable.sol';

contract RockPaperScissors is Ownable {

    uint256 constant moveDeadline = 1 hours;

    enum State {
        none,
        newGame,
        active,
        movesPosted,
        revealed
    }

    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

    enum Outcome {
        None,
        Draw,
        Player1,
        Player2
    }

    struct RevealedMove {
        uint8 move;
        bool revealed;
    }

    struct Game {
        address player1;
        address player2;
        uint256 stake;
        State state;
        uint256 deadline;
        mapping(address => bytes32) movesHash;
        mapping(address => RevealedMove) revealedMoves;
    }

    mapping(bytes32 => Game) public games;
    mapping(uint8 => mapping(uint8 => uint8)) public results;
    mapping(address => uint256) public balances;

    event LogNewGame(
        bytes32 indexed gameId,
        address indexed player1,
        address indexed player2,
        uint256 stake
    );

    event LogJoinedGame(bytes32 indexed gameId, address indexed player2);
    
    event LogHashPosted(
        bytes32 indexed gameId,
        address indexed player,
        bytes32 indexed movesHash
    );

    event LogMoveRevealed(
        bytes32 indexed gameId,
        address indexed player,
        uint8 indexed move,
        bytes32 secretWord
    );

    event LogGameWinner(bytes32 indexed gameId, address indexed winner);

    event LogWithdraw(address indexed player, uint256 indexed value);

    function RockPaperScissors() public  {
        // set results
        results[uint8(Move.Rock)][uint8(Move.Rock)] = uint8(Outcome.Draw);
        results[uint8(Move.Rock)][uint8(Move.Paper)] = uint8(Outcome.Player2);
        results[uint8(Move.Rock)][uint8(Move.Scissors)] = uint8(Outcome.Player1);
        results[uint8(Move.Paper)][uint8(Move.Rock)] = uint8(Outcome.Player1);
        results[uint8(Move.Paper)][uint8(Move.Paper)] = uint8(Outcome.Draw);
        results[uint8(Move.Paper)][uint8(Move.Scissors)] = uint8(Outcome.Player2);
        results[uint8(Move.Scissors)][uint8(Move.Rock)] = uint8(Outcome.Player2);
        results[uint8(Move.Scissors)][uint8(Move.Paper)] = uint8(Outcome.Player1);
        results[uint8(Move.Scissors)][uint8(Move.Scissors)] = uint8(Outcome.Draw);
    }

    modifier onlyPlayer(bytes32 gameId) {
        require(games[gameId].player1 == msg.sender || games[gameId].player2 == msg.sender);
        _;
    }

    modifier inState(bytes32 gameId, State state) {
        require(games[gameId].state == state);
        _;
    }

    function getMoveHash(bytes32 gameId, address player) external view returns (bytes32) {
        return games[gameId].movesHash[player];
    }

    function getRevealedMove(bytes32 gameId, address player) external view returns (uint8) {
        return games[gameId].revealedMoves[player].move;
    }

    function createGameId(address creator, uint256 gameNumber) external pure returns(bytes32) {
        return keccak256(creator, gameNumber);
    }

    function createMoveHash(uint8 move, bytes32 secretWord) public pure returns(bytes32) {
        return keccak256(move, secretWord);
    }

    /**
     * Create game. If coplayer's address is 0x0, it's an open table
     */
    function newGame(bytes32 gameId, address coplayer, bytes32 moveHash)
        public
        payable
        inState(gameId, State.none)
        returns(bool)
    {
        require(coplayer != msg.sender);
        require(moveHash != bytes32(0));

        games[gameId] = Game({
            player1: msg.sender,
            player2: coplayer,
            stake: msg.value,
            state: State.newGame,
            // need that for later
            deadline: now + moveDeadline
        });
        games[gameId].movesHash[msg.sender] = moveHash;
        LogNewGame(gameId, msg.sender, coplayer, msg.value);
        return true;
    }

    function joinGame(bytes32 gameId, uint8 move)
        public
        payable
        inState(gameId, State.newGame)
        returns(bool)
    {
        require(games[gameId].stake == msg.value);
        require(games[gameId].deadline >= now);
        address player1 = games[gameId].player1;
        require(player1 != address(0));
        require(player1 != msg.sender);
        address player2 = games[gameId].player2;
        require(player2 == msg.sender || player2 == address(0));

        games[gameId].player2 = msg.sender;
        games[gameId].stake += msg.value;

        games[gameId].revealedMoves[msg.sender].move = move;
        games[gameId].revealedMoves[msg.sender].revealed = true;
        games[gameId].deadline = now + moveDeadline;
        games[gameId].state = State.movesPosted;

        LogJoinedGame(gameId, msg.sender);
        LogMoveRevealed(gameId, msg.sender, move, '');
        return true;
    }

    function revealMove(bytes32 gameId, uint8 move, bytes32 secretWord)
        public
        onlyPlayer(gameId)
        inState(gameId, State.movesPosted)
        returns(bool)
    {
        // get reference
        Game storage game = games[gameId];

        bytes32 hash = createMoveHash(move, secretWord);
        require(game.movesHash[msg.sender] == hash);

        game.revealedMoves[msg.sender].move = move;
        game.revealedMoves[msg.sender].revealed = true;
        LogMoveRevealed(gameId, msg.sender, move, secretWord);

        game.state = State.revealed;
        address winner = calculateWinner(game);
        
        LogGameWinner(gameId, winner);

        return true;
    }

    /**
     * In canse nobody joins your game, get your funds back
     */
    function cancelGame(bytes32 gameId)
        public
        onlyPlayer(gameId)
        inState(gameId, State.newGame)
        returns(bool)
    {
        Game storage gameRef = games[gameId];
        require(gameRef.deadline < now);
        require(gameRef.player1 == msg.sender);
        balances[msg.sender] += gameRef.stake;
        gameRef.state = State.revealed;
        return true;
    }

    function getRewardPastDeadline(bytes32 gameId)
        public
        onlyPlayer(gameId)
        inState(gameId, State.movesPosted)
        returns(bool)
    {
        Game storage game = games[gameId];
        require(game.revealedMoves[msg.sender].revealed);
        require(game.revealedMoves[game.player1].revealed == false);
        require(game.deadline < now);
        balances[msg.sender] += game.stake;
        game.state = State.revealed;
        return true;
    }

    function withdrawReward() public returns(bool) {
        require(balances[msg.sender] > 0);

        uint256 value = balances[msg.sender];
        balances[msg.sender] = 0;
        msg.sender.transfer(value);
        LogWithdraw(msg.sender, value);
        return true;
    }

    function calculateWinner(Game storage game) internal returns(address) {
        uint8 p1Move = game.revealedMoves[game.player1].move;
        uint8 p2Move = game.revealedMoves[game.player2].move;

        uint8 result = results[p1Move][p2Move];
        address p1 = game.player1;
        address p2 = game.player2;
        uint256 stake = game.stake;

        if(result == uint8(Outcome.Draw)) {
            balances[p1] += stake / 2;
            balances[p2] += stake / 2;
            return address(0);
        } else if (result == uint8(Outcome.Player1)) {
            balances[p1] += stake;
            return p1;
        } else if (result == uint8(Outcome.Player2)) {
            balances[p2] += stake;
            return p2;
        } else if(result == uint8(Outcome.None)) {
            // one of the players or both made illegal moves
            if (results[p1Move][uint8(Move.Scissors)] != uint8(Outcome.None)) {
                balances[p1] += stake / 2;
                balances[getOwner()] += stake / 2;
                return p1;
            } else if(results[uint8(Move.Scissors)][p2Move] != uint8(Outcome.None)) {
                balances[p2] += stake / 2;
                balances[getOwner()] += stake / 2;
                return p2;
            } else {
                // both player sent illegal moves, give stake to owner
                balances[getOwner()] += stake;
                return address(0);
            }
        }
    }
}

