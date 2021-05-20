// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "./ERC20/SafeERC20.sol";


// SteakHouse provides single side farm for IFO of Stake Steak
// This contract is forked from Popsicle.finance which is a fork of SushiSwap's MasterChef Contract
// It intakes one token and allows the user to farm another token. Due to the crosschain nature of Stake Steak we've swapped reward per block
// to reward per second. Moreover, we've implemented safe transfer of reward instead of mint in Masterchef.
// Future is crosschain...

// The contract is ownable untill the DAO will be able to take over.
contract SteakHouse is Ownable {
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 remainingSteakTokenReward;  // STEAK Tokens that weren't distributed for user per pool.
        //
        // We do some fancy math here. Basically, any point in time, the amount of STEAK
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSTEAKPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws Staked tokens to a pool. Here's what happens:
        //   1. The pool's `accSTEAKPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 stakingToken; // Contract address of staked token
        uint256 stakingTokenTotalAmount; //Total amount of deposited tokens
        uint256 accSteakPerShare; // Accumulated STEAK per share, times 1e12. See below.
        uint32 lastRewardTime; // Last timestamp number that STEAK distribution occurs.
        uint16 allocPoint; // How many allocation points assigned to this pool. STEAK to distribute per second.
    }
    
    IERC20 immutable public steak; // The STEAK TOKEN!!

    IERC20 immutable public ifusd; // iFUSD
    
    uint256 public steakPerSecond; // Steak tokens vested per second.

    uint256 public withdrawFee = 5000; // Withdraw Fee

    uint256 public harvestFee = 200000; //Fee for claiming rewards

    address public feeReceiver = owner(); //feeReceiver is originally owner of the contract
    
    PoolInfo[] public poolInfo; // Info of each pool.
    
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes tokens.
    
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.
    
    uint32 immutable public startTime; // The timestamp when STEAK farming starts.
    
    uint32 public endTime; // Time on which the reward calculation should end

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event FeeCollected(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC20 _steak,
        IERC20 _ifusd,
        uint256 _steakPerSecond,
        uint32 _startTime
    ) {
        steak = _steak;
        ifusd = _ifusd;
        
        steakPerSecond = _steakPerSecond;
        startTime = _startTime;
        endTime = _startTime + 30 days;
    }
    
    function changeEndTime(uint32 addSeconds) external onlyOwner {
        endTime += addSeconds;
    }

    // Owner can retreive excess/unclaimed STEAK 7 days after endtime
    // Owner can NOT withdraw any token other than STEAK
    function collect(uint256 _amount) external onlyOwner {
        require(block.timestamp >= endTime + 7 days, "too early to collect");
        uint256 balance = steak.balanceOf(address(this));
        require(_amount <= balance, "withdrawing too much");
        steak.safeTransfer(owner(), _amount);
    }
    
    // Changes Steak token reward per second. Use this function to moderate the `lockup amount`. Essentially this function changes the amount of the reward
    // which is entitled to the user for his token staking by the time the `endTime` is passed.
    //Good practice to update pools without messing up the contract
    function setSteakPerSecond(uint256 _steakPerSecond,  bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        steakPerSecond= _steakPerSecond;
    }
    // How many pools are in the contract
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new staking token to the pool. Can only be called by the owner.
    // VERY IMPORTANT NOTICE 
    // ----------- DO NOT add the same staking token more than once. Rewards will be messed up if you do. -------------
    // Good practice to update pools without messing up the contract
    function add(
        uint16 _allocPoint,
        IERC20 _stakingToken,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime =
            block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint +=_allocPoint;
        poolInfo.push(
            PoolInfo({
                stakingToken: _stakingToken,
                stakingTokenTotalAmount: 0,
                allocPoint: _allocPoint,
                lastRewardTime: uint32(lastRewardTime),
                accSteakPerShare: 0
            })
        );
    }

    // Update the given pool's STEAK allocation point. Can only be called by the owner.
    // Good practice to update pools without messing up the contract
    function set(
        uint256 _pid,
        uint16 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    
    function setWithdrawFee(uint256 _withdrawFee) external onlyOwner{
        require(_withdrawFee <= 50000);
        withdrawFee = _withdrawFee;
    }

    function setHarvestFee(uint256 _harvestFee) external onlyOwner{
        require(_harvestFee <= 1000000);
        harvestFee = _harvestFee;
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner{
        feeReceiver  =_feeReceiver;
    }

    // Return reward multiplier over the given _from to _to time.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        _from = _from > startTime ? _from : startTime;
        if (_from > endTime || _to < startTime) {
            return 0;
        }
        if (_to > endTime) {
            return endTime - _from;
        }
        return _to - _from;
    }

    // View function to see pending STEAK on frontend.
    function pendingSteak(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSteakPerShare = pool.accSteakPerShare;
       
        if (block.timestamp > pool.lastRewardTime && pool.stakingTokenTotalAmount != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 steakReward =
                multiplier * steakPerSecond * pool.allocPoint / totalAllocPoint;
            accSteakPerShare += steakReward * 1e12 / pool.stakingTokenTotalAmount;
        }
        return user.amount * accSteakPerShare / 1e12 - user.rewardDebt + user.remainingSteakTokenReward;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.stakingTokenTotalAmount == 0) {
            pool.lastRewardTime = uint32(block.timestamp);
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 steakReward =
            multiplier * steakPerSecond * pool.allocPoint / totalAllocPoint;
        pool.accSteakPerShare += steakReward * 1e12 / pool.stakingTokenTotalAmount;
        pool.lastRewardTime = uint32(block.timestamp);
    }

    // Deposit staking tokens to SteakHouse for STEAK allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount * pool.accSteakPerShare / 1e12 - user.rewardDebt + user.remainingSteakTokenReward;
            user.remainingSteakTokenReward = safeRewardTransfer(msg.sender, pending);
        }
        uint256 pendingWithdrawFee;
        if (pool.stakingToken != ifusd) {
            pendingWithdrawFee = _amount * withdrawFee / 1000000; //! 0.5% fee for depositing liquidity if not the ifusd pool 
        } 
        pool.stakingToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        pool.stakingToken.safeTransfer(owner(), pendingWithdrawFee);
        uint256 amountToStake = _amount - pendingWithdrawFee;
        user.amount += amountToStake;
        pool.stakingTokenTotalAmount += amountToStake;
        user.rewardDebt = user.amount * pool.accSteakPerShare / 1e12;
        emit Deposit(msg.sender, _pid, amountToStake);
        emit FeeCollected(msg.sender, _pid, pendingWithdrawFee);
    }

    // Withdraw staked tokens from SteakHouse.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "SteakHouse: amount to withdraw is greater than amount available");
        updatePool(_pid);
        uint256 pending =
            user.amount * pool.accSteakPerShare / 1e12 - user.rewardDebt + user.remainingSteakTokenReward;
        user.remainingSteakTokenReward = safeRewardTransfer(msg.sender, pending);
        user.amount -= _amount;
        pool.stakingTokenTotalAmount -= _amount;
        user.rewardDebt = user.amount * pool.accSteakPerShare / 1e12;
        pool.stakingToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }
    
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 userAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.remainingSteakTokenReward = 0;
        pool.stakingToken.safeTransfer(address(msg.sender), userAmount);
        emit EmergencyWithdraw(msg.sender, _pid, userAmount);
    }

    // Safe steak transfer function. Just in case if the pool does not have enough STEAK token,
    // The function returns the amount which is owed to the user
    function safeRewardTransfer(address _to, uint256 _amount) internal returns(uint256) {
        uint256 steakTokenBalance = steak.balanceOf(address(this));
        uint256 pendingHarvestFee = _amount * harvestFee / 1000000; //! 20% fee for harvesting rewards sent back to xSTEAK holders
        if (steakTokenBalance == 0) { //save some gas fee
            return _amount;
        }
        if (_amount > steakTokenBalance) { //save some gas fee
            pendingHarvestFee = steakTokenBalance * harvestFee / 1000000;
            steak.safeTransfer(feeReceiver, pendingHarvestFee);
            steak.safeTransfer(_to, steakTokenBalance - pendingHarvestFee);
            return _amount - steakTokenBalance;
        }
        steak.safeTransfer(feeReceiver, pendingHarvestFee);
        steak.safeTransfer(_to, _amount - pendingHarvestFee);
        return 0;
    }
}
