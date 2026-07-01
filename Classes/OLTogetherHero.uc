class OLTogetherHero extends OLHero;

var SkelControlSingleBone SpinePitchCtrl;
var SkelControlSingleBone SpinePitchCtrlProxy;
var int RemotePitch;

simulated event PostInitAnimTree(SkeletalMeshComponent SkelComp)
{
    Super.PostInitAnimTree(SkelComp);
    if (SkelComp == Mesh)
        InitSpineCtrl();
    if (ShadowProxy != None && SkelComp == ShadowProxy)
        InitSpineCtrlProxy();
}

simulated function InitSpineCtrl()
{
    if (SpinePitchCtrl != None)
        return;
    SpinePitchCtrl = new(self) class'SkelControlSingleBone';
    SpinePitchCtrl.ControlName = 'PitchCtrl';
    SpinePitchCtrl.bApplyRotation = true;
    SpinePitchCtrl.bAddRotation = false;
    SpinePitchCtrl.BoneRotationSpace = BCS_BoneSpace;
    AddSkelControlToMesh('Hero-Spine', SpinePitchCtrl, Mesh);
}

simulated function InitSpineCtrlProxy()
{
    if (SpinePitchCtrlProxy != None)
        return;
    SpinePitchCtrlProxy = new(self) class'SkelControlSingleBone';
    SpinePitchCtrlProxy.ControlName = 'PitchCtrlProxy';
    SpinePitchCtrlProxy.bApplyRotation = true;
    SpinePitchCtrlProxy.bAddRotation = false;
    SpinePitchCtrlProxy.BoneRotationSpace = BCS_BoneSpace;
    AddSkelControlToMesh('Hero-Spine', SpinePitchCtrlProxy, ShadowProxy);
}

simulated function AddSkelControlToMesh(name BoneName, SkelControlBase Ctrl, SkeletalMeshComponent SkelComp)
{
    local AnimTree AT;
    local SkelControlListHead Head;

    if (SkelComp == None || Ctrl == None)
        return;
    AT = AnimTree(SkelComp.Animations);
    if (AT == None)
        return;

    Head.BoneName = BoneName;
    Head.ControlHead = Ctrl;
    AT.SkelControlLists.AddItem(Head);
    Ctrl.SetSkelControlStrength(1.0, 0.0);
}

event Tick(float DeltaTime)
{
    bCameraCracked = false;
    super.Tick(DeltaTime);
    bCameraCracked = false;

    ApplyPitch();
}

simulated function ApplyPitch()
{
    local int ClampedPitch;
    local rotator BoneRot;

    ClampedPitch = RemotePitch;
    if (ClampedPitch > 32768)
        ClampedPitch -= 65536;
    if (ClampedPitch < -12000)
        ClampedPitch = -12000;
    if (ClampedPitch > 12000)
        ClampedPitch = 12000;

    BoneRot.Pitch = ClampedPitch;
    BoneRot.Yaw = 0;
    BoneRot.Roll = 0;

    if (SpinePitchCtrl != None)
        SpinePitchCtrl.BoneRotation = BoneRot;
    if (SpinePitchCtrlProxy != None)
        SpinePitchCtrlProxy.BoneRotation = BoneRot;
}

DefaultProperties
{
    RemotePitch=0
}
