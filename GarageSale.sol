pragma solidity ^0.4.13;

contract GarageSale {
  
  enum Modes { Inactive, Disabled, Test, Live }
    Modes public mode = Modes.Inactive;

  address salesman;

 //having a big clean-out of the garage, let's keep track of what we can hand down. 
  string public name = "Junk";
  uint8 public decimals = 0;

  uint256 public totalSupply = 250; // from a very big gargage, 250 pieces of crap can be given out. 
  uint public remainingCrap = 250; // 
  uint public crapSold = 0;

  bytes5[250] public PileOfCrap; //lists who bought what

  bytes32 public searchSeed = 0x0; // gets set with the immediately preceding blockhash when the contract is activated to prevent "premining"

  struct OfferCrapTo {
    bool exists;
    bytes5 stuffId;
    address salesman;
    uint price;
    address keepSafeFor;
  }

  struct AskForCrap{
    bool exists;
    bytes5 stuffId;
    address potentialBuyer;
    uint price;
  }

  mapping (bytes5 => OfferCrapTo) public OfferCrapTos;
  mapping (bytes5 => AskForCrap) public AskForCraps;


  mapping (bytes5 => address) public AllBuyers; 
  mapping (address => uint256) public balanceOf; //number of stuff owned by a given address
  mapping (address => uint) public pendingWithdrawals; // requests that are being processed.

  /* events */

  event StuffPickedUp(address indexed to, bytes5 indexed stuffId);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event StuffBought(bytes5 indexed stuffId, uint price, address indexed from, address indexed to);
  event OfferedCrapTo(bytes5 indexed stuffId, uint price, address indexed toAddress);
  event OfferedCrapCanceled(bytes5 indexed stuffId);
  event AskedForCrap(bytes5 indexed stuffId, uint price, address indexed from);
  event AskedForCrapCancelled(bytes5 indexed stuffId);
  
 //constructor, makes sure everything got loaded okay. 
  function GarageSale() payable {
    salesman = msg.sender;
    assert(remainingCrap == totalSupply);
    assert(PileOfCrap.length == totalSupply);
    assert(crapSold == 0);
  }

  /* If someone found crap laying around and is picking it up, this registers that */
  
  function PickUp(bytes32 seed) activeMode returns (bytes5 stuffId) {
    require(remainingCrap > 0); //If everything is sold we cant execute this function. 
    bytes32 stuffIdHash = keccak256(seed, searchSeed); // generate a hashcode for all stuff. (why you'd do this much effort in the real world if a different question)
    require(stuffIdHash[0] | stuffIdHash[1] | stuffIdHash[2] == 0x0); //check just to be sure if hash is valid
   require(AllBuyers[stuffId] == 0x0); // if someone else bought this crap before you did, throw an error. We don't know how to clone stuff yet.

    PileOfCrap[crapSold] = stuffId;
    crapSold++;

    AllBuyers[stuffId] = msg.sender;
    balanceOf[msg.sender]++;
    remainingCrap--;

    StuffPickedUp(msg.sender, stuffId);

    return stuffId;
  }


  // Offer crap to anyone looking to pick up 
  function pickUpStuff(bytes5 stuffId, uint price) onlyBuyer(stuffId) {
    require(price > 0);
    OfferCrapTos[stuffId] = OfferCrapTo(true, stuffId, msg.sender, price, 0x0);
    OfferedCrapTo(stuffId, price, 0x0);
  }


 // cancel an offer on crap
  function CancelOffer(bytes5 stuffId) onlyBuyer(stuffId) {
    OfferCrapTos[stuffId] = OfferCrapTo(false, stuffId, 0x0, 0, 0x0);
    OfferedCrapCanceled(stuffId);
  }

  // accepts an offer  
  function acceptThisOffer(bytes5 stuffId) payable {
  OfferCrapTo storage offer = OfferCrapTos[stuffId];
    require(offer.exists);
    require(offer.keepSafeFor == 0x0 || offer.keepSafeFor == msg.sender); // make sure it is not sold to someone else
    require(msg.value >= offer.price); // make sure whoever is bidding on stuff isn't broke
    if(msg.value > offer.price) {
      pendingWithdrawals[msg.sender] += (msg.value - offer.price); // if the submitted amount exceeds the price allow the buyer to withdraw the difference
    }
    transferStuff(stuffId, AllBuyers[stuffId], msg.sender, offer.price);
  }

  // Give away some stuff to the less fortunate 
  function donateStuff(bytes5 stuffId, address to) onlyBuyer(stuffId) {
    transferStuff(stuffId, msg.sender, to, 0);
  }

  //make an ETH offer and bid on random crap.
  function bidOnCrap(bytes5 stuffId) payable isNotSender(AllBuyers[stuffId]) {
    require(AllBuyers[stuffId] != 0x0); // it has to still be there obviously
    AskForCrap storage existingRequest = AskForCraps[stuffId];
    require(msg.value > 0);
    require(msg.value > existingRequest.price);


    if(existingRequest.price > 0) {
      pendingWithdrawals[existingRequest.potentialBuyer] += existingRequest.price;
    }

    AskForCraps[stuffId] = AskForCrap(true, stuffId, msg.sender, msg.value);
   AskedForCrap(stuffId, msg.value, msg.sender);

  }

  // if you want to sell, the owner can accept the offer 
  function AcceptOffer(bytes5 stuffId) onlyBuyer(stuffId) {
    AskForCrap storage existingRequest = AskForCraps[stuffId];
    require(existingRequest.exists);
    address existingRequester = existingRequest.potentialBuyer;
    uint existingPrice = existingRequest.price;
   AskForCraps[stuffId] = AskForCrap(false, stuffId, 0x0, 0); // a requester could quickly cancel the request, after transfer is activated, and end up not paying anything. 
    transferStuff(stuffId, msg.sender, existingRequester, existingPrice);
  }



  function withdraw() {
    uint amount = pendingWithdrawals[msg.sender];
    pendingWithdrawals[msg.sender] = 0;
    msg.sender.transfer(amount);
  }

  /* buyer only functions */

  /* disable contract before activation. A safeguard if a bug is found before the contract is activated */
  function disableBeforeActivation() onlyOwner inactiveMode {
    mode = Modes.Disabled;  // once the contract is disabled it's mode cannot be changed
  }

  /* activates the contract in *Live* mode which sets the searchSeed and enables rescuing */
  function activate() onlyOwner inactiveMode {
    mode = Modes.Live; // once the contract is activated it's mode cannot be changed
  }

  /* activates the contract in *Test* mode which sets the searchSeed and enables rescuing */
  function activateInTestMode() onlyOwner inactiveMode { //
    mode = Modes.Test; // once the contract is activated it's mode cannot be changed
  }

 
  /* aggregate getters */

  function getStuffIds() constant returns (bytes5[]) {
    bytes5[] memory stuffIds = new bytes5[](crapSold);
    for (uint i = 0; i < crapSold; i++) {
      stuffIds[i] = PileOfCrap[i];
    }
    return stuffIds;
  }


  /* modifiers */
  modifier onlyOwner() {
    require(msg.sender == salesman);
    _;
  }

  modifier inactiveMode() {
    require(mode == Modes.Inactive);
    _;
  }

  modifier activeMode() {
    require(mode == Modes.Live || mode == Modes.Test);
    _;
  }

  modifier onlyBuyer(bytes5 stuffId) {
    require(AllBuyers[stuffId] == msg.sender);
    _;
  }

  modifier isNotSender(address a) {
    require(msg.sender != a);
    _;
  }

  //private so it can only be called if valid. 
  function transferStuff(bytes5 stuffId, address from, address to, uint price) private {
    AllBuyers[stuffId] = to;
    balanceOf[from]--;
    balanceOf[to]++;
    OfferCrapTos[stuffId] = OfferCrapTo(false, stuffId, 0x0, 0, 0x0); // cancel any existing adoption offer when cat is transferred

    AskForCrap storage request = AskForCraps[stuffId]; //if the recipient has a pending adoption request, cancel it
    if(request.potentialBuyer == to) {
      pendingWithdrawals[to] += request.price;
      AskForCraps[stuffId] = AskForCrap(false, stuffId, 0x0, 0);
    }

    pendingWithdrawals[from] += price;

    Transfer(from, to, 1);
    StuffBought(stuffId, price, from, to);
  }

}s
