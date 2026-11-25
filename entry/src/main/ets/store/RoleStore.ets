import { StorageService } from '../service/StorageService';

export enum UserRole {
  INDIVIDUAL = 0,
  TEACHER = 1
}

const KEY_ROLE = 'selected_role';
const KEY_SELECTED = 'role_selected';

const ROLE_LABELS: string[] = ['个人模式', '监护者模式'];
const ROLE_DESCS: string[] = [
  '监测自己的脑电数据，玩游戏、做训练',
  '多设备监测，查看多名学生的脑电状态'
];

export class RoleStore {
  private static instance: RoleStore;
  private role: UserRole = UserRole.INDIVIDUAL;
  private selected: boolean = false;

  static getInstance(): RoleStore {
    if (!RoleStore.instance) {
      RoleStore.instance = new RoleStore();
    }
    return RoleStore.instance;
  }

  init(): void {
    const svc = StorageService.getInstance();
    const v = svc.getNumber(KEY_SELECTED, 0);
    this.selected = v === 1;
    if (this.selected) {
      const r = svc.getNumber(KEY_ROLE, UserRole.INDIVIDUAL);
      this.role = (r >= 0 && r <= 1) ? r as UserRole : UserRole.INDIVIDUAL;
    }
  }

  getRole(): UserRole {
    return this.role;
  }

  isSelected(): boolean {
    return this.selected;
  }

  setRole(role: UserRole): void {
    this.role = role;
    this.selected = true;
    const svc = StorageService.getInstance();
    svc.setNumber(KEY_ROLE, role);
    svc.setNumber(KEY_SELECTED, 1);
  }

  resetRole(): void {
    this.selected = false;
    StorageService.getInstance().setNumber(KEY_SELECTED, 0);
  }

  getRoleLabel(): string {
    return ROLE_LABELS[this.role] || '个人模式';
  }

  static getLabel(role: UserRole): string {
    return ROLE_LABELS[role] || '个人模式';
  }

  static getDesc(role: UserRole): string {
    return ROLE_DESCS[role] || '';
  }

  isIndividual(): boolean {
    return this.role === UserRole.INDIVIDUAL;
  }

  isTeacher(): boolean {
    return this.role === UserRole.TEACHER;
  }

  // 功能门控
  canPlayGames(): boolean {
    return this.role === UserRole.INDIVIDUAL;
  }

  canTrain(): boolean {
    return this.role === UserRole.INDIVIDUAL;
  }

  canUseSoothing(): boolean {
    return this.role === UserRole.INDIVIDUAL;
  }

  canViewAllDevices(): boolean {
    return this.role === UserRole.TEACHER;
  }
}
