# Automatic Model Retraining Guide

This guide explains how to set up automatic retraining of the AI energy optimization model.

## Why Retrain?

- Models perform better with fresh data
- Adapts to changing energy consumption patterns
- Maintains accuracy over time
- Improves recommendation quality

## Retraining Script

The script `scripts/schedule_retraining.py` is ready to use. It:
- Trains the model with the latest 7 days of data
- Logs training progress and results
- Handles errors gracefully
- Saves the model automatically

## Setup Options

### Option 1: Windows Task Scheduler (Recommended for Windows)

1. **Open Task Scheduler**
   - Press `Win + R`, type `taskschd.msc`, press Enter

2. **Create Basic Task**
   - Click "Create Basic Task" in the right panel
   - Name: "VoltGuard AI Model Retraining"
   - Description: "Retrain AI energy optimization model daily"

3. **Set Trigger**
   - Choose "Daily"
   - Set time (e.g., 2:00 AM)
   - Click Next

4. **Set Action**
   - Action: "Start a program"
   - Program/script: `python` (or full path to python.exe)
   - Arguments: `scripts\schedule_retraining.py`
   - Start in: `C:\Users\User\voltguard\Volt-Guard\backend` (your backend directory)
   - Click Next

5. **Review and Finish**
   - Review settings
   - Check "Open the Properties dialog for this task"
   - Click Finish

6. **Configure Properties** (Optional)
   - General tab: Check "Run whether user is logged on or not"
   - Settings tab: Configure retry options if task fails

### Option 2: Linux Cron (Recommended for Linux)

1. **Open crontab**
   ```bash
   crontab -e
   ```

2. **Add entry** (runs daily at 2 AM)
   ```bash
   0 2 * * * cd /path/to/Volt-Guard/backend && python scripts/schedule_retraining.py >> logs/retraining.log 2>&1
   ```

3. **Save and exit**
   - Press `Ctrl+X`, then `Y`, then Enter

4. **Verify**
   ```bash
   crontab -l
   ```

### Option 3: systemd Service (Linux - Advanced)

1. **Create service file**
   ```bash
   sudo nano /etc/systemd/system/voltguard-retraining.service
   ```

2. **Add configuration**
   ```ini
   [Unit]
   Description=VoltGuard AI Model Retraining
   After=network.target

   [Service]
   Type=oneshot
   User=your-user
   WorkingDirectory=/path/to/Volt-Guard/backend
   ExecStart=/usr/bin/python3 scripts/schedule_retraining.py
   StandardOutput=append:/path/to/Volt-Guard/backend/logs/retraining.log
   StandardError=append:/path/to/Volt-Guard/backend/logs/retraining.log

   [Install]
   WantedBy=multi-user.target
   ```

3. **Create timer file**
   ```bash
   sudo nano /etc/systemd/system/voltguard-retraining.timer
   ```

4. **Add timer configuration**
   ```ini
   [Unit]
   Description=Run VoltGuard AI Model Retraining Daily
   Requires=voltguard-retraining.service

   [Timer]
   OnCalendar=daily
   OnCalendar=*-*-* 02:00:00
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

5. **Enable and start**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable voltguard-retraining.timer
   sudo systemctl start voltguard-retraining.timer
   ```

6. **Check status**
   ```bash
   sudo systemctl status voltguard-retraining.timer
   ```

### Option 4: Manual Execution

You can also run the script manually:

```bash
cd backend
python scripts/schedule_retraining.py
```

## Logging

Training logs are saved to:
- **Location**: `backend/logs/retraining.log`
- **Format**: Timestamp, level, message
- **Includes**: Training progress, performance metrics, errors

## Monitoring

### Check Logs

**Windows:**
```powershell
Get-Content backend\logs\retraining.log -Tail 50
```

**Linux:**
```bash
tail -f backend/logs/retraining.log
```

### Verify Model File

Check that the model file is updated:
```bash
# Windows
dir backend\models\energy_optimizer.pkl

# Linux
ls -lh backend/models/energy_optimizer.pkl
```

### Test Model

After retraining, test the model:
```bash
python backend/scripts/test_recommendations.py
```

## Recommended Schedule

- **Daily**: Best for rapidly changing environments
- **Weekly**: Good balance for most scenarios
- **Monthly**: Acceptable for stable environments

**Default**: Daily at 2:00 AM (low usage time)

## Customization

Edit `scripts/schedule_retraining.py` to customize:

1. **Training days** (default: 7)
   ```python
   results = optimizer.train_model(days=14)  # Use 14 days
   ```

2. **Model type** (default: 'random_forest')
   ```python
   results = optimizer.train_model(model_type='gradient_boosting')
   ```

3. **Location/Module filters**
   ```python
   results = optimizer.train_model(location='LAB_1')
   ```

## Troubleshooting

### Task/Job Not Running

1. **Check logs** for error messages
2. **Verify Python path** is correct
3. **Check file permissions** (read/write access)
4. **Test manually** first to ensure script works

### Model Performance Degrades

1. **Increase training days** (use more historical data)
2. **Try different model type** (gradient_boosting vs random_forest)
3. **Check data quality** (ensure clean data is available)
4. **Review logs** for warnings or errors

### Out of Memory

1. **Reduce training days**
2. **Filter by location/module** (train on subset)
3. **Increase system RAM**
4. **Use gradient_boosting** (uses less memory than random_forest)

## Best Practices

1. **Monitor regularly**: Check logs weekly
2. **Backup models**: Keep previous model versions
3. **Test after retraining**: Run test script to verify
4. **Schedule during low usage**: Train during off-peak hours
5. **Set up alerts**: Notify on training failures

## Integration with CI/CD

For automated deployments, you can integrate retraining:

```yaml
# Example GitHub Actions workflow
name: Retrain AI Model
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:

jobs:
  retrain:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-python@v2
        with:
          python-version: '3.9'
      - name: Install dependencies
        run: |
          cd backend
          pip install -r requirements.txt
      - name: Retrain model
        run: |
          cd backend
          python scripts/schedule_retraining.py
```

---

**Ready to automate!** Choose the option that works best for your environment.

