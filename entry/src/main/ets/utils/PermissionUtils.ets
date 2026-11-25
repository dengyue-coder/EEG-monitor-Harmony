import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

/**
 * 运行时权限工具：鸿蒙 NEXT 中 ACCESS_BLUETOOTH 为
 * user_grant 权限，必须在运行时调用 requestPermissionsFromUser 动态申请，
 * 否则对应 API 会直接抛 201（Permission denied），扫描静默失败。
 */

const BLUETOOTH_PERMISSION: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';

/** 查询权限是否已授权 */
export async function checkPermissionGranted(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = context.applicationInfo.accessTokenId;
    const grant = await atManager.checkAccessToken(tokenId, permission);
    return grant === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (e) {
    return false;
  }
}

/** 确保蓝牙权限：未授权时弹系统授权框 */
export async function ensureBluetoothPermission(context: common.UIAbilityContext): Promise<boolean> {
  const granted = await checkPermissionGranted(context, BLUETOOTH_PERMISSION);
  if (granted) return true;
  return requestPermission(context, BLUETOOTH_PERMISSION);
}

async function requestPermission(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context, [permission]);
    const results = result.authResults;
    if (results.length > 0 && results[0] === 0) {
      return true;
    }
  } catch (e) {
    // 授权流程异常
  }
  return false;
}
